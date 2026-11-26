variable "libvirt_uri" {
  description = "libvirt connection URI."
  type        = string
  default     = "qemu:///system"
}

variable "pool_path" {
  description = "Directory of the lab's own libvirt storage pool. Set in ~/.config/k8s-flightsim/host.tfvars."
  type        = string
  default     = "/var/lib/libvirt/images/k8s-flightsim"
}

variable "disk_cache" {
  description = "QEMU cache mode of the VM disks. null keeps the libvirt default. \"unsafe\" ignores guest flushes: much faster etcd on slow disks, but a host crash can corrupt the disks and their snapshots. Lab only."
  type        = string
  default     = null

  validation {
    condition     = var.disk_cache == null || contains(["default", "none", "writethrough", "writeback", "directsync", "unsafe"], coalesce(var.disk_cache, "default"))
    error_message = "disk_cache must be null or a libvirt cache mode: default, none, writethrough, writeback, directsync, unsafe."
  }
}

variable "prefix" {
  description = "Prefix for libvirt object names (domains, volumes)."
  type        = string
  default     = "k8s-flightsim"
}

variable "bridge_name" {
  description = "Host bridge of the lab network (Linux limit: 15 characters)."
  type        = string
  default     = "virbr-fsim"

  validation {
    condition     = length(var.bridge_name) <= 15
    error_message = "Interface names are limited to 15 characters."
  }
}

variable "network_cidr" {
  description = "NAT network for the lab. The first host address is the gateway."
  type        = string
  default     = "10.17.3.0/24"
}

variable "dns_domain" {
  description = "DNS domain of the lab. .internal is reserved for private networks."
  type        = string
  default     = "k8s-flightsim.internal"
}

variable "gateway_ip" {
  description = "LoadBalancer IP of the ingress gateway. Every name under dns_domain without an own record resolves to it."
  type        = string
  default     = "10.17.3.100"
}

variable "api_vip" {
  description = "Virtual IP of the Kubernetes API, held by kube-vip."
  type        = string
  default     = "10.17.3.10"
}

variable "os_image_url" {
  description = "Ubuntu minimal cloud image (same kernel as the server image, about 280 instead of 660 packages). Downloaded once into the pool."
  type        = string
  default     = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
}

variable "vm_user" {
  description = "Login user created by cloud-init."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Public key injected into the nodes."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "nodes" {
  description = "Cluster nodes. role is control_plane or worker. data_disk_gb > 0 adds a second disk, e.g. for Longhorn."
  type = map(object({
    role         = string
    ip           = string
    mac          = string
    vcpus        = number
    memory_mb    = number
    disk_gb      = number
    data_disk_gb = optional(number, 0)
  }))

  default = {
    cp1 = { role = "control_plane", ip = "10.17.3.11", mac = "52:54:00:17:03:11", vcpus = 2, memory_mb = 3072, disk_gb = 20 }
    cp2 = { role = "control_plane", ip = "10.17.3.12", mac = "52:54:00:17:03:12", vcpus = 2, memory_mb = 3072, disk_gb = 20 }
    cp3 = { role = "control_plane", ip = "10.17.3.13", mac = "52:54:00:17:03:13", vcpus = 2, memory_mb = 3072, disk_gb = 20 }
    w1  = { role = "worker", ip = "10.17.3.21", mac = "52:54:00:17:03:21", vcpus = 2, memory_mb = 4096, disk_gb = 30 }
    w2  = { role = "worker", ip = "10.17.3.22", mac = "52:54:00:17:03:22", vcpus = 2, memory_mb = 4096, disk_gb = 30 }
    w3  = { role = "worker", ip = "10.17.3.23", mac = "52:54:00:17:03:23", vcpus = 2, memory_mb = 4096, disk_gb = 30 }
  }

  validation {
    condition     = alltrue([for n in values(var.nodes) : contains(["control_plane", "worker"], n.role)])
    error_message = "role must be control_plane or worker."
  }

  validation {
    condition     = length([for n in values(var.nodes) : n if n.role == "control_plane"]) % 2 == 1
    error_message = "etcd needs an odd number of control plane nodes."
  }
}
