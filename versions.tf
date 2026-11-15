terraform {
  # 1.15 adds explicit type constraints on outputs. Write-only attributes (data_wo) need 1.11.
  required_version = ">= 1.15"

  # A module declares a lower bound only: the live repository pins exact versions.
  # No `provider` block in a module: the caller configures helm, kubernetes and kubectl from the kubeconfig.
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
    # 3.2.1 fixes "Missing Resource Identity After Create" on the write-only data_wo attribute used for the repository tokens.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.1"
    }
    # Applies the Gateway API CRDs without a cluster at plan time (kubernetes_manifest needs one).
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 3.0.1"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.0"
    }
  }
}
