locals {
  k3s_nodes = { for node in var.k3s_nodes : node.name => node }
}

resource "proxmox_vm_qemu" "k3s" {
  for_each = local.k3s_nodes

  name        = each.value.name
  target_node = each.value.target_node
  clone       = var.template_name
  full_clone  = true

  # Cloud-init and agent
  os_type = "cloud-init"
  agent   = 1

  # Problem: 120 seconds is too short if cloud-init takes time to configure DHCP
  # Fix: increase timeout or do not wait for IP
  #agent_timeout = 300 # 5 minutes

  # New: wait longer after cloning and before starting
  #clone_wait      = 15
  #additional_wait = 10

  # Resources
  memory = var.vm_memory_mb



  cpu {
    cores   = var.vm_cores
    sockets = var.vm_sockets
    type    = "host" # Improvement: better performance
  }

  # Disk
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disk {
    slot    = "scsi0"
    size    = "${var.vm_disk_gb}G"
    type    = "disk"
    storage = var.vm_storage
    # Improvement: enable iothread for better I/O
    #iothread = true
  }

  disk {
    slot    = "ide2"
    type    = "cloudinit"
    storage = var.vm_storage
  }
  serial {
    id   = 0
    type = "socket"
  }
  # Network
  network {
    id        = 0
    model     = "virtio"
    bridge    = var.vm_bridge
    firewall  = false
    link_down = false

  }

  # Cloud-init
  ipconfig0 = "ip=dhcp"
  ciuser    = var.vm_user
  sshkeys   = var.ssh_public_key

  # Additional configuration
  onboot = true
  tags   = "k3s,${each.value.role}"

  # Improvement: ignore network changes after creation
  # Prevent Terraform from trying to "fix" changes made by cloud-init
  lifecycle {
    ignore_changes = [
      network,
      disk, # Prevent issues if the disk grows
    ]
  }
}
