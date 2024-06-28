# Let's Encrypt cluster issuer
resource "kubernetes_manifest" "letsencrypt_cluster_issuer" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = var.issuer_kind
    "metadata" = {
      "name" = var.issuer_name
    }
    "spec" = {
      "acme" = {
        "email" = var.issuer_email
        "privateKeySecretRef" = {
          "name" = var.issuer_private_key
        }
        "server" = var.ca_server
        "solvers" = [
          {
            "http01" = {
              "ingress" = {
                "class" = "gce"
              }
            }
          },
        ]
      }
    }
  }
  depends_on = [helm_release.cert-manager]
}