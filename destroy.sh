#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform"
TFVARS_FILE="${TFVARS_FILE:-$TF_DIR/terraform.tfvars}"

START_TS="$(date +%s)"
START_HUMAN="$(date +"%Y-%m-%d %H:%M:%S %Z")"

HOSTS_BEGIN="# BEGIN K3S PROXMOX LAB"
HOSTS_END="# END K3S PROXMOX LAB"

RUN_AS_HOME="$HOME"
RUN_AS_CMD=()
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  if command -v getent >/dev/null 2>&1; then
    RUN_AS_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  else
    RUN_AS_HOME="/home/$SUDO_USER"
  fi
  RUN_AS_CMD=(sudo -u "$SUDO_USER" -H)
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

remove_hosts_block() {
  local hosts_file="/etc/hosts"
  local tmp_file
  tmp_file="$(mktemp)"

  awk -v begin="$HOSTS_BEGIN" -v end="$HOSTS_END" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$hosts_file" > "$tmp_file"

  if [ "$(id -u)" -eq 0 ]; then
    cp "$tmp_file" "$hosts_file"
  else
    sudo cp "$tmp_file" "$hosts_file"
  fi

  rm -f "$tmp_file"
}

collect_cleanup_targets() {
  local outputs_file="$1"
  local targets_file="$2"

  python3 - "$outputs_file" "$targets_file" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    outputs = json.load(fh)

names = outputs.get("k3s_vm_names", {}).get("value", [])
ips = outputs.get("k3s_vm_ipv4", {}).get("value", {})

targets = []
for name in names:
    targets.append(name)
for ip in ips.values():
    if ip and re.match(r"^\d{1,3}(\.\d{1,3}){3}$", ip):
        targets.append(ip)

seen = set()
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    for item in targets:
        if item in seen:
            continue
        seen.add(item)
        fh.write(f"{item}\n")
PY
}

clean_known_hosts() {
  local targets_file="$1"
  local known_hosts="$RUN_AS_HOME/.ssh/known_hosts"

  if ! command -v ssh-keygen >/dev/null 2>&1; then
    return 0
  fi

  if [ ! -f "$known_hosts" ]; then
    return 0
  fi

  while IFS= read -r target; do
    if [ -z "$target" ]; then
      continue
    fi
    if [ "${#RUN_AS_CMD[@]}" -gt 0 ]; then
      "${RUN_AS_CMD[@]}" ssh-keygen -f "$known_hosts" -R "$target" >/dev/null 2>&1 || true
    else
      ssh-keygen -f "$known_hosts" -R "$target" >/dev/null 2>&1 || true
    fi
  done < "$targets_file"
}

require_cmd terraform
require_cmd python3

outputs_file="$(mktemp)"
targets_file="$(mktemp)"
trap 'rm -f "$outputs_file" "$targets_file"' EXIT

if terraform -chdir="$TF_DIR" output -json > "$outputs_file" 2>/dev/null; then
  collect_cleanup_targets "$outputs_file" "$targets_file"
else
  : > "$targets_file"
fi

log "Terraform init..."
terraform -chdir="$TF_DIR" init

destroy_start="$(date +%s)"
log "Terraform destroy..."
terraform -chdir="$TF_DIR" destroy -auto-approve
destroy_end="$(date +%s)"

log "Limpiando /etc/hosts..."
remove_hosts_block

log "Limpiando known_hosts..."
clean_known_hosts "$targets_file"

if [ "${CLEAN_TERRAFORM:-}" = "1" ]; then
  log "Eliminando estado local de Terraform..."
  rm -f "$TF_DIR/terraform.tfstate" "$TF_DIR/terraform.tfstate.backup"
  rm -rf "$TF_DIR/.terraform" "$TF_DIR/.terraform.lock.hcl"
fi

END_TS="$(date +%s)"
END_HUMAN="$(date +"%Y-%m-%d %H:%M:%S %Z")"

echo
echo "=== Resumen ==="
echo "Inicio:   $START_HUMAN"
echo "Fin:      $END_HUMAN"
echo "Total:    $(format_duration $((END_TS - START_TS)))"
echo "Destroy:  $(format_duration $((destroy_end - destroy_start)))"
if [ -s "$targets_file" ]; then
  echo "Hosts limpiados:"
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    echo "  - $target"
  done < "$targets_file"
fi
