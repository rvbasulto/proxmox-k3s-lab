variable "proxmox_api_url" {
  description = "Proxmox API endpoint, e.g. https://pve.example:8006/api2/json."
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID in the form user@realm!token."
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Allow insecure TLS connections to the Proxmox API."
  type        = bool
  default     = false
}

variable "template_name" {
  description = "Name of the Proxmox VM template to clone."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init."
  type        = string
}

variable "vm_user" {
  description = "Cloud-init user name."
  type        = string
  default     = "ubuntu"
}

variable "vm_cores" {
  description = "Number of vCPU cores per VM."
  type        = number
  default     = 2
}

variable "vm_sockets" {
  description = "Number of CPU sockets per VM."
  type        = number
  default     = 1
}

variable "vm_memory_mb" {
  description = "Memory per VM in MB."
  type        = number
  default     = 4096
}

variable "vm_disk_gb" {
  description = "Disk size per VM in GB."
  type        = number
  default     = 30
}

variable "vm_storage" {
  description = "Proxmox storage backend for disks and cloud-init."
  type        = string
  default     = "local-lvm"
}

variable "vm_bridge" {
  description = "Network bridge name."
  type        = string
  default     = "vmbr0"
}

variable "k3s_nodes" {
  description = "Definition of k3s VMs to provision."
  type = list(object({
    name        = string
    target_node = string
    role        = string
  }))
  default = [
    {
      name        = "k3s-server-01"
      target_node = "pve"
      role        = "server"
    },
    {
      name        = "k3s-agent-01"
      target_node = "pve02"
      role        = "agent"
    },
    {
      name        = "k3s-agent-02"
      target_node = "pve03"
      role        = "agent"
    }
  ]
}
