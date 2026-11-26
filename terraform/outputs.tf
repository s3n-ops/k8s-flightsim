output "api_endpoint" {
  description = "Kubernetes API endpoint (kube-vip)."
  value       = "https://${var.api_vip}:6443"
}

output "nodes" {
  description = "Node name to IP."
  value       = { for name, n in var.nodes : name => n.ip }
}

output "domains" {
  description = "libvirt domain names, control plane first."
  value       = [for name in concat(local.control_plane, local.workers) : libvirt_domain.node[name].name]
}
