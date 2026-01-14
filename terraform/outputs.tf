output "k3s_vm_names" {
  description = "Names of provisioned k3s VMs."
  value       = [for vm in proxmox_vm_qemu.k3s : vm.name]
}

output "k3s_vm_nodes" {
  description = "Mapping of VM names to Proxmox nodes."
  value       = { for name, vm in proxmox_vm_qemu.k3s : name => vm.target_node }
}

output "k3s_vm_ipv4" {
  description = "Mapping of VM names to IPv4 addresses as reported by the guest agent."
  value       = { for name, vm in proxmox_vm_qemu.k3s : name => vm.default_ipv4_address }
}
