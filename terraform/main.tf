locals {
  gateway        = cidrhost(var.network_cidr, 1)
  prefix_length  = tonumber(split("/", var.network_cidr)[1])
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  data_disks = { for name, n in var.nodes : name => n if n.data_disk_gb > 0 }

  # Control plane first, so cp1 is always the init node.
  control_plane = sort([for name, n in var.nodes : name if n.role == "control_plane"])
  workers       = sort([for name, n in var.nodes : name if n.role == "worker"])
}

# Storage pool
resource "libvirt_pool" "lab" {
  name   = var.prefix
  type   = "dir"
  target = { path = var.pool_path }
  create = { build = true, start = true, autostart = true }
}

# Network
# NAT network without DHCP: every node gets a static address via cloud-init.
# No autostart: `just start` starts it, `just stop` stops it again.
resource "libvirt_network" "lab" {
  name      = var.prefix
  autostart = false

  bridge  = { name = var.bridge_name }
  forward = { mode = "nat" }
  # register: libvirt (10.1+) tells systemd-resolved on the host to send
  # queries for this domain to the lab DNS on this bridge. No host config.
  domain = { name = var.dns_domain, local_only = "yes", register = "yes" }

  ips = [{
    address = local.gateway
    prefix  = local.prefix_length
  }]

  # Nodes and the API VIP get their own records. Host records take
  # precedence over the wildcard below in dnsmasq.
  dns = {
    host = concat(
      [{ ip = var.api_vip, hostnames = [{ hostname = "api.${var.dns_domain}" }] }],
      [for name, n in var.nodes : { ip = n.ip, hostnames = [{ hostname = "${name}.${var.dns_domain}" }] }],
    )
  }

  # Wildcard: every other name under the domain points to the gateway.
  dnsmasq_options = {
    option = [{ value = "address=/${var.dns_domain}/${var.gateway_ip}" }]
  }
}

# Volumes
# All disks are sparse qcow2. Root disks are copy-on-write overlays of one
# shared base image. Guests pass TRIM through (discard = unmap), and zero
# writes become holes (detect_zeros = unmap).
resource "libvirt_volume" "base" {
  name   = "${var.prefix}-base-${basename(var.os_image_url)}"
  pool   = libvirt_pool.lab.name
  target = { format = { type = "qcow2" } }
  create = { content = { url = var.os_image_url } }
}

resource "libvirt_volume" "root" {
  for_each = var.nodes

  name          = "${var.prefix}-${each.key}-root.qcow2"
  pool          = libvirt_pool.lab.name
  allocation    = 0 # sparse: blocks are allocated on first write
  capacity      = each.value.disk_gb
  capacity_unit = "GiB"
  target        = { format = { type = "qcow2" } }

  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "data" {
  for_each = local.data_disks

  name          = "${var.prefix}-${each.key}-data.qcow2"
  pool          = libvirt_pool.lab.name
  allocation    = 0 # sparse: blocks are allocated on first write
  capacity      = each.value.data_disk_gb
  capacity_unit = "GiB"
  target        = { format = { type = "qcow2" } }
}

# cloud-init
resource "libvirt_cloudinit_disk" "seed" {
  for_each = var.nodes

  name = "${var.prefix}-${each.key}-seed"

  meta_data = yamlencode({
    "instance-id"    = "${var.prefix}-${each.key}"
    "local-hostname" = each.key
  })

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname       = each.key
    dns_domain     = var.dns_domain
    vm_user        = var.vm_user
    ssh_public_key = local.ssh_public_key
    api_vip        = var.api_vip
    nodes          = var.nodes
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    mac           = each.value.mac
    ip            = each.value.ip
    prefix_length = local.prefix_length
    gateway       = local.gateway
    dns_domain    = var.dns_domain
  })
}

resource "libvirt_volume" "seed" {
  for_each = var.nodes

  name   = "${var.prefix}-${each.key}-seed.iso"
  pool   = libvirt_pool.lab.name
  target = { format = { type = "iso" } }
  create = { content = { url = libvirt_cloudinit_disk.seed[each.key].path } }
}

# Domains
resource "libvirt_domain" "node" {
  for_each = var.nodes

  name        = "${var.prefix}-${each.key}"
  description = "k8s-flightsim ${each.value.role} ${each.key}"
  type        = "kvm"
  running     = true
  autostart   = false

  # Power state belongs to `just start` and `just stop` after creation.
  lifecycle {
    ignore_changes = [running]
  }

  vcpu        = each.value.vcpus
  memory      = each.value.memory_mb
  memory_unit = "MiB"

  cpu = { mode = "host-passthrough" }

  # The provider sets no features by default. Without ACPI and APIC a q35
  # guest hangs early in boot. virt-install sets both automatically.
  features = {
    acpi = true
    apic = {}
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }

  devices = {
    disks = [for d in [
      {
        device = "disk"
        source = { volume = { pool = libvirt_pool.lab.name, volume = libvirt_volume.root[each.key].name } }
        target = { dev = "vda", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2", discard = "unmap", detect_zeros = "unmap", cache = var.disk_cache }
      },
      {
        device = "disk"
        source = { volume = { pool = libvirt_pool.lab.name, volume = try(libvirt_volume.data[each.key].name, "") } }
        target = { dev = "vdb", bus = "virtio" }
        driver = { name = "qemu", type = "qcow2", discard = "unmap", detect_zeros = "unmap", cache = var.disk_cache }
      },
      # Seed on virtio, not on a SATA cdrom: the minimal image loads ahci too
      # late for ds-identify, which then disables cloud-init. virtio-blk is
      # built into the kernel. NoCloud finds the disk by its label cidata.
      {
        device    = "disk"
        read_only = true
        source    = { volume = { pool = libvirt_pool.lab.name, volume = libvirt_volume.seed[each.key].name } }
        target    = { dev = "vdc", bus = "virtio" }
        driver    = { name = "qemu", type = "raw" }
      },
    ] : d if d.source.volume.volume != ""]

    interfaces = [{
      model  = { type = "virtio" }
      mac    = { address = each.value.mac }
      source = { network = { network = libvirt_network.lab.name } }
    }]

    # No source: libvirt defaults to a pty, which `virsh console` uses.
    consoles = [{
      target = { type = "serial", port = 0 }
    }]

    channels = [{
      source = { unix = {} }
      target = { virt_io = { name = "org.qemu.guest_agent.0" } }
    }]
  }
}

# Ansible inventory
resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory.yml"
  file_permission = "0644"

  content = join("", [
    "# Generated by Terraform (terraform/main.tf). Do not edit.\n",
    yamlencode({
      all = {
        vars = {
          ansible_user  = var.vm_user
          api_vip       = var.api_vip
          dns_domain    = var.dns_domain
          libvirt_uri   = var.libvirt_uri
          domain_prefix = var.prefix
        }
        children = {
          control_plane = { hosts = { for name in local.control_plane : name => { ansible_host = var.nodes[name].ip } } }
          workers       = { hosts = { for name in local.workers : name => { ansible_host = var.nodes[name].ip } } }
        }
      }
    }),
  ])
}
