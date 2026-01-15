#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"
TFVARS_FILE="${TFVARS_FILE:-$TF_DIR/terraform.tfvars}"

IP_WAIT_SECONDS="${IP_WAIT_SECONDS:-300}"
IP_WAIT_INTERVAL="${IP_WAIT_INTERVAL:-10}"

START_TS="$(date +%s)"
START_HUMAN="$(date +"%Y-%m-%d %H:%M:%S %Z")"

HOSTS_BEGIN="# BEGIN K3S PROXMOX LAB"
HOSTS_END="# END K3S PROXMOX LAB"

ANSIBLE_RUN_CMD=()
RUN_AS_HOME="$HOME"
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  if command -v getent >/dev/null 2>&1; then
    RUN_AS_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  else
    RUN_AS_HOME="/home/$SUDO_USER"
  fi
  ANSIBLE_RUN_CMD=(sudo -u "$SUDO_USER" -H)
fi

log() {
  printf "\n[%s] %s\n" "$(date +"%H:%M:%S")" "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Falta el comando requerido: $1" >&2
    exit 1
  fi
}

format_duration() {
  local total="$1"
  local hours=$((total / 3600))
  local minutes=$(((total % 3600) / 60))
  local seconds=$((total % 60))
  printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

tfvars_get() {
  local key="$1"
  local file="$2"

  if [ ! -f "$file" ]; then
    return 0
  fi

  python3 - "$key" "$file" <<'PY'
import re
import sys

key = sys.argv[1]
path = sys.argv[2]
pattern = re.compile(rf'^\s*{re.escape(key)}\s*=\s*"([^"]*)"')

with open(path, "r", encoding="utf-8") as fh:
    for line in fh:
        if line.lstrip().startswith(("#", "//")):
            continue
        match = pattern.search(line)
        if match:
            print(match.group(1))
            break
PY
}

parse_outputs() {
  local outputs_file="$1"
  local hosts_block="$2"

  python3 - "$outputs_file" "$hosts_block" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    outputs = json.load(fh)

names = outputs.get("k3s_vm_names", {}).get("value", [])
ips = outputs.get("k3s_vm_ipv4", {}).get("value", {})

lines = []
missing = []
for name in names:
    ip = ips.get(name)
    if ip and re.match(r"^\d{1,3}(\.\d{1,3}){3}$", ip):
        lines.append(f"{ip} {name}")
    else:
        missing.append(name)

with open(sys.argv[2], "w", encoding="utf-8") as fh:
    for line in lines:
        fh.write(f"{line}\n")

print(f"total={len(names)}")
print(f"missing={len(missing)}")
print("missing_names=" + ",".join(missing))
PY
}

update_hosts() {
  local hosts_block="$1"
  local hosts_file="/etc/hosts"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v begin="$HOSTS_BEGIN" -v end="$HOSTS_END" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$hosts_file" > "$tmp_file"

  {
    echo "$HOSTS_BEGIN"
    cat "$hosts_block"
    echo "$HOSTS_END"
  } >> "$tmp_file"

  if [ "$(id -u)" -eq 0 ]; then
    cp "$tmp_file" "$hosts_file"
  else
    sudo cp "$tmp_file" "$hosts_file"
  fi

  rm -f "$tmp_file"
}

require_cmd terraform
require_cmd ansible-playbook
require_cmd python3

SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-}"
if [ -z "$SSH_PRIVATE_KEY" ]; then
  TF_SSH_PUBLIC_KEY="$(tfvars_get ssh_public_key "$TFVARS_FILE")"
  if [ -n "$TF_SSH_PUBLIC_KEY" ]; then
    for pub_key in "$RUN_AS_HOME"/.ssh/*.pub; do
      if [ -f "$pub_key" ] && grep -Fqx "$TF_SSH_PUBLIC_KEY" "$pub_key"; then
        candidate="${pub_key%.pub}"
        if [ -f "$candidate" ]; then
          SSH_PRIVATE_KEY="$candidate"
          break
        fi
      fi
    done
  fi

  if [ -z "$SSH_PRIVATE_KEY" ]; then
    for candidate in "$RUN_AS_HOME/.ssh/id_ed25519" "$RUN_AS_HOME/.ssh/id_rsa"; do
      if [ -f "$candidate" ]; then
        SSH_PRIVATE_KEY="$candidate"
        break
      fi
    done
  fi
fi

if [ -z "$SSH_PRIVATE_KEY" ] && [ -z "${SSH_AUTH_SOCK:-}" ]; then
  log "Aviso: no se detecto llave SSH ni SSH_AUTH_SOCK; Ansible puede fallar por permisos."
fi

outputs_file="$(mktemp)"
hosts_block="$(mktemp)"
trap 'rm -f "$outputs_file" "$hosts_block"' EXIT

log "Terraform init..."
terraform -chdir="$TF_DIR" init

tf_start="$(date +%s)"
log "Terraform apply..."
terraform -chdir="$TF_DIR" apply -auto-approve
tf_end="$(date +%s)"

log "Esperando IPs reportadas por el guest agent..."
waited=0
total=0
missing=0
missing_names=""

while true; do
  terraform -chdir="$TF_DIR" output -json > "$outputs_file"
  while IFS= read -r line; do
    case "$line" in
      total=*) total="${line#total=}" ;;
      missing=*) missing="${line#missing=}" ;;
      missing_names=*) missing_names="${line#missing_names=}" ;;
    esac
  done < <(parse_outputs "$outputs_file" "$hosts_block")

  if [ "$total" -eq 0 ]; then
    echo "No se encontraron VMs en los outputs de Terraform." >&2
    exit 1
  fi

  if [ "$missing" -eq 0 ]; then
    break
  fi

  if [ "$waited" -ge "$IP_WAIT_SECONDS" ]; then
    echo "Timeout esperando IPs. Faltan: $missing_names" >&2
    exit 1
  fi

  log "Aun faltan IPs: $missing_names. Reintentando en ${IP_WAIT_INTERVAL}s..."
  sleep "$IP_WAIT_INTERVAL"
  waited=$((waited + IP_WAIT_INTERVAL))
done

log "Actualizando /etc/hosts..."
update_hosts "$hosts_block"

ansible_start="$(date +%s)"
log "Ejecutando Ansible..."
ANSIBLE_KEY_ARGS=()
if [ -n "$SSH_PRIVATE_KEY" ]; then
  ANSIBLE_KEY_ARGS=(--private-key "$SSH_PRIVATE_KEY")
fi

ANSIBLE_USER_ARGS=()
TF_VM_USER="$(tfvars_get vm_user "$TFVARS_FILE")"
if [ -n "$TF_VM_USER" ]; then
  ANSIBLE_USER_ARGS=(-u "$TF_VM_USER")
fi

if [ "${#ANSIBLE_RUN_CMD[@]}" -gt 0 ]; then
  log "Detectado sudo. Ansible se ejecutara como $SUDO_USER para usar sus llaves SSH."
  "${ANSIBLE_RUN_CMD[@]}" env ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" \
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" \
    "${ANSIBLE_KEY_ARGS[@]}" "${ANSIBLE_USER_ARGS[@]}"
else
  ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" \
    ansible-playbook -i "$ANSIBLE_DIR/inventory/hosts.ini" "$ANSIBLE_DIR/site.yml" \
    "${ANSIBLE_KEY_ARGS[@]}" "${ANSIBLE_USER_ARGS[@]}"
fi
ansible_end="$(date +%s)"

END_TS="$(date +%s)"
END_HUMAN="$(date +"%Y-%m-%d %H:%M:%S %Z")"

echo
echo "=== Resumen ==="
echo "Inicio:  $START_HUMAN"
echo "Fin:     $END_HUMAN"
echo "Total:   $(format_duration $((END_TS - START_TS)))"
echo "Terraform: $(format_duration $((tf_end - tf_start)))"
echo "Ansible:   $(format_duration $((ansible_end - ansible_start)))"
echo "VMs:     $total"
echo "IPs:"

python3 - "$outputs_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    outputs = json.load(fh)

names = outputs.get("k3s_vm_names", {}).get("value", [])
ips = outputs.get("k3s_vm_ipv4", {}).get("value", {})
nodes = outputs.get("k3s_vm_nodes", {}).get("value", {})

for name in names:
    ip = ips.get(name, "")
    node = nodes.get(name, "")
    suffix = f" (node: {node})" if node else ""
    print(f"  - {name}: {ip}{suffix}")
PY
