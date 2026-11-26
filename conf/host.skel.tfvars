# k8s-flightsim host settings, skeleton.
#
# `just init` copies this file to ~/.config/k8s-flightsim/host.tfvars if no
# configuration exists there. The copy is yours: it is never overwritten.
# This skeleton may change with new releases; compare it with your copy
# after an update.

# Directory of the lab's libvirt storage pool. Changing it on a built lab
# moves the pool, and Terraform replaces all VMs.
pool_path = "/srv/libvirt/k8s-flightsim"

# QEMU cache mode of the VM disks. Unset keeps the safe libvirt default.
# "unsafe" ignores guest flushes. etcd fsyncs on every write; on a slow
# disk (consumer SATA SSD, encryption) leases expire and control plane pods
# restart. "unsafe" fixes that, but a host crash or power loss can corrupt
# the VM disks and their snapshots. Lab only, never in production.
# disk_cache = "unsafe"
