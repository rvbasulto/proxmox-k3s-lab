locals {
  k3s_nodes = { for node in var.k3s_nodes : node.name => node }
}

resource "proxmox_vm_qemu" "k3s" {
  for_each = local.k3s_nodes

  name        = each.value.name
  target_node = each.value.target_node
  clone       = var.template_name
  full_clone  = true

  os_type  = "cloud-init"
  agent    = 1
  cores    = var.vm_cores
  sockets  = var.vm_sockets
  memory   = var.vm_memory_mb
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disk {
    slot     = 0
    size     = "${var.vm_disk_gb}G"
    type     = "scsi"
    storage  = var.vm_storage
    iothread = 1
  }

  network {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  ipconfig0                = "ip=dhcp"
  ciuser                   = var.vm_user
  sshkeys                  = var.ssh_public_key
  cloudinit_cdrom_storage  = var.vm_storage
  onboot                   = true
  tags                     = "k3s,${each.value.role}"
}
