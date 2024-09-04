# Topo LVM Controller Install
resource "helm_release" "topo_lvm" {
  name             = "topo-lvm"
  repository       = "https://topolvm.github.io/topolvm"
  chart            = "topolvm"
  namespace        = "kube-system"
  create_namespace = false
  wait             = "false"
  version          = "14.1.2"

  values = [
    file(join("/", [path.module, "helm_values", "topo_lvm.yaml"]))
  ]

  depends_on = [kubernetes_manifest.letsencrypt_cluster_issuer]
}