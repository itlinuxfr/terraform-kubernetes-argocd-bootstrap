# Bootstraps GitOps on a new cluster: Gateway API CRDs, Cilium, Argo CD, the repository credentials and the root Application.
# It runs once. Argo CD then manages Cilium and itself from Git, so the two Helm releases ignore every change here:
# change a chart version or a value in the Git repository, never in this module.
#
# Order: CRDs, Cilium (the network), the namespace and the credentials, Argo CD, then the root Application.
# The credentials exist before Argo CD starts, so the first sync of the root Application finds the repository.

locals {
  # Talos: no kube-proxy (Cilium replaces it), the API server through KubePrism (localhost:7445, reachable before any Service exists),
  # the cgroup that Talos already mounts and no SYS_MODULE capability.
  cilium_talos_values = yamlencode({
    ipam                 = { mode = "kubernetes" }
    kubeProxyReplacement = true
    k8sServiceHost       = "localhost"
    k8sServicePort       = 7445
    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }
    securityContext = {
      capabilities = {
        ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
        cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
      }
    }
  })

  cilium_values = var.cilium == null ? [] : concat(var.cilium.talos ? [local.cilium_talos_values] : [], var.cilium.values)

  # Created after the Argo CD release: the chart installs the Application CRD, and Helm validates every object before it installs anything,
  # so the Application cannot travel in the chart values (extraObjects).
  root_application = var.root == null ? null : {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = var.root.name, namespace = var.namespace }
    spec = {
      project = var.root.project
      source = {
        repoURL        = var.root.repo_url
        targetRevision = var.root.revision
        path           = var.root.path
      }
      destination = { server = "https://kubernetes.default.svc", namespace = var.namespace }
      syncPolicy  = { automated = { prune = true, selfHeal = true } }
    }
  }

  # The map is sensitive, its keys are not.
  repository_names = nonsensitive(keys(var.repositories))
}

# --- Gateway API CRDs -----------------------------------------------------------------------------------------------
data "http" "gateway_api" {
  count = var.gateway_api == null ? 0 : 1

  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api.version}/${var.gateway_api.channel}-install.yaml"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Cannot download the Gateway API ${var.gateway_api.version} CRDs (HTTP ${self.status_code})."
    }
  }
}

data "kubectl_file_documents" "gateway_api" {
  count = var.gateway_api == null ? 0 : 1

  content = data.http.gateway_api[0].response_body
}

# Server-side apply: the CRDs are too large for the last-applied annotation.
resource "kubectl_manifest" "gateway_api" {
  for_each = var.gateway_api == null ? {} : data.kubectl_file_documents.gateway_api[0].manifests

  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = true
}

# --- Cilium ---------------------------------------------------------------------------------------------------------
resource "helm_release" "cilium" {
  count = var.cilium == null ? 0 : 1

  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium.version
  values     = local.cilium_values
  wait       = true
  timeout    = 900

  depends_on = [kubectl_manifest.gateway_api]

  # Argo CD owns Cilium from now on.
  lifecycle {
    ignore_changes = all
  }
}

# --- Namespace and repository credentials ---------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace
  }

  # Argo CD owns the namespace labels from now on.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }

  depends_on = [helm_release.cilium]
}

# The revision changes with the content, so a rotated token updates the secret although write-only values never reach the state.
resource "kubernetes_secret_v1" "repository" {
  for_each = toset(local.repository_names)

  metadata {
    name      = "repo-${each.key}"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels    = { "argocd.argoproj.io/secret-type" = nonsensitive(var.repositories[each.key].template) ? "repo-creds" : "repository" }
  }

  data_wo = {
    type     = "git"
    url      = var.repositories[each.key].url
    username = var.repositories[each.key].username
    password = var.repositories[each.key].password
  }
  data_wo_revision = parseint(substr(sha256(jsonencode(var.repositories[each.key])), 0, 8), 16)
}

# --- Argo CD and the root Application -------------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd.version
  values     = var.argocd.values
  wait       = true
  timeout    = 900

  depends_on = [kubernetes_secret_v1.repository]

  # Argo CD owns itself from now on.
  lifecycle {
    ignore_changes = all
  }
}

# No finalizer: deleting the root Application must never delete the applications it created, Cilium included.
resource "kubectl_manifest" "root" {
  count = var.root == null ? 0 : 1

  yaml_body = yamlencode(local.root_application)

  depends_on = [helm_release.argocd]
}
