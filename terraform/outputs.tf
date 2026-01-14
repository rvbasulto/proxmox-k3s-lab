output "k3s_vm_name" {
  description = "Name of the provisioned k3s VM."
  value       = proxmox_vm_qemu.k3s.name
}

output "k3s_vm_node" {
  description = "Proxmox node where the VM is provisioned."
  value       = proxmox_vm_qemu.k3s.target_node
}
