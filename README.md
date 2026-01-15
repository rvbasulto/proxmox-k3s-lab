# Proxmox k3s Lab

This repository provisions a reproducible 3-node k3s cluster on Proxmox using Terraform for infrastructure and Ansible for configuration. The control plane runs on `k3s-server-01` and two workers run on `k3s-agent-01` and `k3s-agent-02`.

## Prerequisites

- Proxmox with an Ubuntu 24.04 cloud-init template available.
- API token with VM creation rights.
- Terraform 1.6+ and Ansible installed locally.
- DNS or DHCP-based name resolution for the VM hostnames.

## Repository Layout

- `terraform/` - Proxmox VM provisioning.
- `ansible/` - Inventory, playbooks, and roles.

## Workflow

1. Configure Terraform variables:

   - Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and fill in values.

2. Provision the VMs:

   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

3. Ensure name resolution for the VMs (DNS or `/etc/hosts`). The inventory uses hostnames, not IPs.

4. Configure the cluster:

   ```bash
   cd ansible
   ansible-playbook site.yml
   ```

## One-command deploy

Use the helper script to run Terraform, update `/etc/hosts`, and execute Ansible:

```bash
./deploy.sh
```

Note: it uses `sudo` to update `/etc/hosts` on your local machine.

## One-command destroy

Use the helper script to destroy everything and clean local host entries:

```bash
./destroy.sh
```

Optional: remove local Terraform state and plugin cache:

```bash
CLEAN_TERRAFORM=1 ./destroy.sh
```

## Notes

- All VMs are cloned from the same template, use `vmbr0` with DHCP, and store disks on `local-lvm`.
- QEMU guest agent is enabled for all nodes.
- The k3s server kubeconfig is located at `/etc/rancher/k3s/k3s.yaml` on `k3s-server-01`.
