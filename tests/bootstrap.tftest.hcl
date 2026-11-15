# Tests without a cluster: mock providers, and forced answers for the download of the Gateway API CRDs.
# A mock cannot tell what a real Argo CD does with the values: the chart rendering and the adoption are checked on a cluster.

mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "kubectl" {}
mock_provider "http" {}

override_data {
  target = data.http.gateway_api[0]
  values = {
    status_code   = 200
    response_body = "mock"
  }
}

override_data {
  target = data.kubectl_file_documents.gateway_api[0]
  values = {
    manifests = {
      "/apis/apiextensions.k8s.io/v1/customresourcedefinitions/gateways.gateway.networking.k8s.io"   = "kind: CustomResourceDefinition"
      "/apis/apiextensions.k8s.io/v1/customresourcedefinitions/httproutes.gateway.networking.k8s.io" = "kind: CustomResourceDefinition"
    }
  }
}

variables {
  argocd = { version = "10.18.0" }
}

run "argocd_only" {
  command = plan

  assert {
    condition     = length(helm_release.cilium) == 0 && length(kubectl_manifest.gateway_api) == 0 && length(kubernetes_secret_v1.repository) == 0
    error_message = "Without options the module installs Argo CD only: no Cilium, no CRDs, no credentials."
  }

  assert {
    condition     = length(helm_release.argocd.values) == 0 && length(kubectl_manifest.root) == 0 && output.root_application == null
    error_message = "Without a root Application nothing else is created and the Argo CD values stay as the caller gave them."
  }

  assert {
    condition     = kubernetes_namespace_v1.argocd.metadata[0].name == "argocd" && output.namespace == "argocd"
    error_message = "The namespace must default to argocd."
  }
}

run "everything" {
  command = plan

  variables {
    gateway_api = { version = "v1.6.3" }
    cilium      = { version = "1.20.4" }
    argocd      = { version = "10.18.0", values = ["server:\n  replicas: 1\n"] }
    repositories = {
      platform = { url = "https://github.com/OWNER/platform.git", password = "token-a" }
      github   = { url = "https://github.com/OWNER", password = "token-b", template = true }
    }
    root = { repo_url = "https://github.com/OWNER/platform.git", path = "clusters/demo" }
  }

  assert {
    condition     = length(kubectl_manifest.gateway_api) == 2 && alltrue([for m in kubectl_manifest.gateway_api : m.server_side_apply])
    error_message = "Every Gateway API CRD must be applied server-side."
  }

  assert {
    condition     = helm_release.cilium[0].version == "1.20.4" && helm_release.cilium[0].namespace == "kube-system"
    error_message = "Cilium must be installed in kube-system with the requested version."
  }

  assert {
    condition     = yamldecode(helm_release.cilium[0].values[0]).kubeProxyReplacement == true && yamldecode(helm_release.cilium[0].values[0]).k8sServicePort == 7445
    error_message = "The Talos values must replace kube-proxy and use KubePrism."
  }

  assert {
    condition     = kubernetes_secret_v1.repository["platform"].metadata[0].labels["argocd.argoproj.io/secret-type"] == "repository" && kubernetes_secret_v1.repository["github"].metadata[0].labels["argocd.argoproj.io/secret-type"] == "repo-creds"
    error_message = "A template must become a repo-creds secret and a repository a repository secret."
  }

  assert {
    condition     = kubernetes_secret_v1.repository["platform"].data_wo_revision != kubernetes_secret_v1.repository["github"].data_wo_revision
    error_message = "The revision must depend on the content of each repository."
  }

  # The root Application is created apart from the chart: the chart installs its CRD, and Helm validates every object before installing.
  assert {
    condition     = length(helm_release.argocd.values) == 1 && yamldecode(helm_release.argocd.values[0]).server.replicas == 1 && !strcontains(helm_release.argocd.values[0], "extraObjects")
    error_message = "The caller values must come first."
  }

  assert {
    condition     = yamldecode(kubectl_manifest.root[0].yaml_body).kind == "Application" && yamldecode(kubectl_manifest.root[0].yaml_body).spec.source.path == "clusters/demo"
    error_message = "The root Application must read the path that the caller gave."
  }

  assert {
    condition     = !can(yamldecode(kubectl_manifest.root[0].yaml_body).metadata.finalizers)
    error_message = "The root Application must have no finalizer: deleting it must never delete Cilium."
  }

  assert {
    condition     = yamldecode(kubectl_manifest.root[0].yaml_body).metadata.namespace == "argocd" && output.root_application == "root"
    error_message = "The root Application lives in the Argo CD namespace and is named root."
  }
}

run "cilium_without_talos_values" {
  command = plan

  variables {
    cilium = { version = "1.20.4", talos = false, values = ["hubble:\n  enabled: true\n"] }
  }

  assert {
    condition     = length(helm_release.cilium[0].values) == 1 && yamldecode(helm_release.cilium[0].values[0]).hubble.enabled == true
    error_message = "With talos = false only the caller values reach Cilium."
  }
}

run "other_namespace" {
  command = plan

  variables {
    namespace = "gitops"
    root      = { repo_url = "https://github.com/OWNER/platform.git", path = "clusters/demo", name = "apps", revision = "v2" }
  }

  assert {
    condition     = helm_release.argocd.namespace == "gitops" && yamldecode(kubectl_manifest.root[0].yaml_body).metadata.namespace == "gitops" && yamldecode(kubectl_manifest.root[0].yaml_body).spec.source.targetRevision == "v2"
    error_message = "The namespace, the name and the revision must follow the variables."
  }
}

run "gateway_api_version_must_be_a_tag" {
  command = plan

  variables {
    gateway_api = { version = "1.6.3" }
  }

  expect_failures = [var.gateway_api]
}

run "gateway_api_channel_is_checked" {
  command = plan

  variables {
    gateway_api = { version = "v1.6.3", channel = "beta" }
  }

  expect_failures = [var.gateway_api]
}
