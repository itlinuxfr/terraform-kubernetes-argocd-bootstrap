# GitOps on a new Talos cluster: the Gateway API CRDs, Cilium, Argo CD, a read-only token for the platform repository and the root Application.
# In a real project, pin the module source to a tag:
#   source = "git::https://github.com/itlinuxfr/terraform-kubernetes-argocd-bootstrap.git?ref=v1.0.0"
# The relative source is used by CI: it tests the code of the current branch.
#
# The cluster must exist and answer. With cni = "none" its nodes stay NotReady until Cilium is installed: this module installs it.
# Configure the three providers from the kubeconfig of the cluster (the example reads a file; a live repository can read the output of the cluster module).

terraform {
  required_version = ">= 1.15"

  # The kubectl provider is not a HashiCorp one: without its source, Terraform looks for hashicorp/kubectl.
  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.5" }
    kubectl    = { source = "alekc/kubectl", version = "~> 3.0" }
  }
}

variable "argocd_repo_token" {
  description = "Read-only token for the platform repository."
  type        = string
  sensitive   = true
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
}

module "platform" {
  source = "../../"

  # The release that your Cilium version documents (Cilium 1.20 documents Gateway API v1.6.3).
  gateway_api = { version = "v1.6.3" }
  cilium      = { version = "1.20.4" }
  argocd      = { version = "10.18.0" }

  repositories = {
    platform = { url = "https://github.com/OWNER/platform.git", password = var.argocd_repo_token }
  }

  # Argo CD reads clusters/demo in the repository and creates everything else from there.
  root = { repo_url = "https://github.com/OWNER/platform.git", path = "clusters/demo" }
}
