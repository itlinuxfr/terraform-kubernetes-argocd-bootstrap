variable "namespace" {
  description = "Namespace of Argo CD. The module creates it."
  type        = string
  default     = "argocd"
  nullable    = false
}

variable "gateway_api" {
  description = "Gateway API CRDs to install before Cilium (Cilium does not install them). Use the release that your Cilium version documents. Set to null to skip."
  type = object({
    version = string
    channel = optional(string, "experimental")
  })
  default = null

  validation {
    condition     = var.gateway_api == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.gateway_api.version))
    error_message = "gateway_api.version must be a release tag such as v1.6.3."
  }

  validation {
    condition     = var.gateway_api == null || contains(["standard", "experimental"], var.gateway_api.channel)
    error_message = "gateway_api.channel must be standard or experimental."
  }
}

variable "cilium" {
  description = <<-EOT
    Installs Cilium (the CNI) once, because Argo CD cannot start without a network. Argo CD takes it over afterwards: give it the same chart version.
    `talos` adds the values that Talos needs (kube-proxy replacement, KubePrism, cgroup). With `gateway_api` set, Cilium starts with the Gateway API on. `values` are YAML documents merged after them.
    Set to null when the cluster already has a CNI.
  EOT
  type = object({
    version = string
    talos   = optional(bool, true)
    values  = optional(list(string), [])
  })
  default = null
}

variable "argocd" {
  description = "Argo CD Helm chart (argo-cd): its version and its values, as YAML documents. Argo CD should manage itself afterwards from the same chart version."
  type = object({
    version = string
    values  = optional(list(string), [])
  })
  nullable = false
}

variable "repositories" {
  description = <<-EOT
    Git repositories that Argo CD reads, by name. A `template` entry is a credential template: its url is a prefix shared by every repository below it.
    The secrets are written with a write-only attribute: the tokens stay out of the Terraform state.
  EOT
  type = map(object({
    url      = string
    password = string
    username = optional(string, "git")
    template = optional(bool, false)
  }))
  default   = {}
  sensitive = true
  nullable  = false
}

variable "root" {
  description = <<-EOT
    The root Application (app of apps): it makes Argo CD read `path` in the repository and create everything else from there.
    It has no finalizer, so deleting it never deletes the applications it created (Cilium included). Set to null to create none.
  EOT
  type = object({
    repo_url = string
    path     = string
    revision = optional(string, "main")
    name     = optional(string, "root")
    project  = optional(string, "default")
  })
  default = null
}
