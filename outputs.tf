output "namespace" {
  description = "Namespace of Argo CD."
  type        = string
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "root_application" {
  description = "Name of the root Application, or null when none is created."
  type        = string
  value       = var.root == null ? null : var.root.name
}
