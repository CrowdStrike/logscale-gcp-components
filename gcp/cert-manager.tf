# Install cert-manager CRDs
resource "null_resource" "install_cert_manager" {
  provisioner "local-exec" {
    command = "kubectl apply -f ${var.cm_crds_url}"
  }
}

# Cert-manager Kubernetes namespace
resource "kubernetes_namespace" "cert-manager" {
  metadata {
    name = var.cm_namespace
  }
}

# Cert-manager helm release
resource "helm_release" "cert-manager" {
  name       = "cert-manager"
  repository = var.cm_repo
  chart      = "cert-manager"
  namespace  = var.cm_namespace
  version    = var.cm_version
  values = [
    <<-EOT
    ingressShim:
      defaultIssuerName: var.issuer_name
      defaultIssuerKind: var.issuer_kind
    EOT
  ]
  depends_on = [
    kubernetes_namespace.cert-manager,
    null_resource.install_cert_manager
  ]
}