locals {
  k3s_nodes = { for node in var.k3s_nodes : node.name => node }
}

resource "proxmox_vm_qemu" "k3s" {
  for_each = local.k3s_nodes

  name        = each.value.name
  target_node = each.value.target_node
  clone       = var.template_name
  full_clone  = true

  # Cloud-init y Agent
  os_type = "cloud-init"
  agent   = 1

  # PROBLEMA: 120 segundos es muy poco si cloud-init tarda en configurar DHCP
  # SOLUCIÓN: Aumentar timeout O no esperar por IP
  #agent_timeout = 300 # 5 minutos

  # NUEVO: Esperar más después de clonar y antes de iniciar
  #clone_wait      = 15
  #additional_wait = 10

  # Recursos
  memory = var.vm_memory_mb



  cpu {
    cores   = var.vm_cores
    sockets = var.vm_sockets
    type    = "host" # MEJORA: Mejor rendimiento
  }

  # Disco
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"

  disk {
    slot    = "scsi0"
    size    = "${var.vm_disk_gb}G"
    type    = "disk"
    storage = var.vm_storage
    # MEJORA: Habilitar iothread para mejor I/O
    iothread = true
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
  # Red
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

  # Configuración adicional
  onboot = true
  tags   = "k3s,${each.value.role}"

  # MEJORA: Ignorar cambios en red después de crear
  # Evita que Terraform intente "arreglar" cosas que cloud-init cambia
  lifecycle {
    ignore_changes = [
      network,
      disk, # Evita problemas si el disco crece
    ]
  }
}
