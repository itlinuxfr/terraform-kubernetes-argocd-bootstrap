# terraform-kubernetes-argocd-bootstrap

Bootstraps GitOps on a new Kubernetes cluster: Gateway API CRDs, Cilium, Argo CD, the credentials of the Git repositories and the root Application (app of apps). It runs once: Argo CD then manages Cilium and itself from Git.

## Usage

```hcl
module "platform" {
  source = "git::https://github.com/itlinuxfr/terraform-kubernetes-argocd-bootstrap.git?ref=v1.0.0"

  gateway_api = { version = "v1.6.3" } # the release that your Cilium version documents
  cilium      = { version = "1.20.4" }
  argocd      = { version = "10.18.0" }

  repositories = {
    platform = { url = "https://github.com/itlinuxfr/platform.git", password = var.argocd_repo_token }
  }

  root = { repo_url = "https://github.com/itlinuxfr/platform.git", path = "clusters/demo" }

  # No depends_on on this module: the providers read the kubeconfig of the cluster, which orders the creation.
}
```

The caller configures the `helm`, `kubernetes` and `kubectl` providers from the kubeconfig of the cluster, and declares `alekc/kubectl` in its `required_providers` (without a source Terraform looks for `hashicorp/kubectl`). See [`examples/talos`](examples/talos/).

## How it works
1. **Gateway API CRDs** (optional), applied server-side. Cilium needs them and does not install them.
2. **Cilium** (optional), once, with the values that Talos needs. Without a CNI Argo CD cannot start.
3. **The namespace and the repository credentials**, before Argo CD, so that its first sync finds the repository. The tokens are written with a write-only attribute: they never reach the Terraform state.
4. **Argo CD**, from its Helm chart.
5. **The root Application** (app of apps), without finalizer: deleting it never deletes the applications it created, Cilium included.

The two Helm releases ignore every later change. Argo CD manages Cilium and itself from the Git repository, with the same chart versions: change a version or a value there, never here.

Do not add `depends_on` to the module call: it defers the download of the CRDs to apply time, and the plan of a new cluster fails (`for_each` over a value known only after apply). The providers read the kubeconfig of the cluster, which already orders the creation.

See the [`examples/`](examples/) directory for complete examples.

## Contributing
Read [`AGENTS.md`](AGENTS.md) for conventions and commands, and [`SECURITY.md`](SECURITY.md) for security rules.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0.0 |
| <a name="requirement_http"></a> [http](#requirement\_http) | >= 3.4.0 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | >= 3.0.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.2.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0.0 |
| <a name="provider_http"></a> [http](#provider\_http) | >= 3.4.0 |
| <a name="provider_kubectl"></a> [kubectl](#provider\_kubectl) | >= 3.0.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 3.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [helm_release.argocd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubectl_manifest.gateway_api](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubectl_manifest.root](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.argocd](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.repository](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [http_http.gateway_api](https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http) | data source |
| [kubectl_file_documents.gateway_api](https://registry.terraform.io/providers/alekc/kubectl/latest/docs/data-sources/file_documents) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_argocd"></a> [argocd](#input\_argocd) | Argo CD Helm chart (argo-cd): its version and its values, as YAML documents. Argo CD should manage itself afterwards from the same chart version. | <pre>object({<br/>    version = string<br/>    values  = optional(list(string), [])<br/>  })</pre> | n/a | yes |
| <a name="input_cilium"></a> [cilium](#input\_cilium) | Installs Cilium (the CNI) once, because Argo CD cannot start without a network. Argo CD takes it over afterwards: give it the same chart version.<br/>`talos` adds the values that Talos needs (kube-proxy replacement, KubePrism, cgroup). `values` are YAML documents merged after them.<br/>Set to null when the cluster already has a CNI. | <pre>object({<br/>    version = string<br/>    talos   = optional(bool, true)<br/>    values  = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_gateway_api"></a> [gateway\_api](#input\_gateway\_api) | Gateway API CRDs to install before Cilium (Cilium does not install them). Use the release that your Cilium version documents. Set to null to skip. | <pre>object({<br/>    version = string<br/>    channel = optional(string, "experimental")<br/>  })</pre> | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of Argo CD. The module creates it. | `string` | `"argocd"` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Git repositories that Argo CD reads, by name. A `template` entry is a credential template: its url is a prefix shared by every repository below it.<br/>The secrets are written with a write-only attribute: the tokens stay out of the Terraform state. | <pre>map(object({<br/>    url      = string<br/>    password = string<br/>    username = optional(string, "git")<br/>    template = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_root"></a> [root](#input\_root) | The root Application (app of apps): it makes Argo CD read `path` in the repository and create everything else from there.<br/>It has no finalizer, so deleting it never deletes the applications it created (Cilium included). Set to null to create none. | <pre>object({<br/>    repo_url = string<br/>    path     = string<br/>    revision = optional(string, "main")<br/>    name     = optional(string, "root")<br/>    project  = optional(string, "default")<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace of Argo CD. |
| <a name="output_root_application"></a> [root\_application](#output\_root\_application) | Name of the root Application, or null when none is created. |
<!-- END_TF_DOCS -->
