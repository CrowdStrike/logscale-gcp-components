# Topo LVM Init install
resource "helm_release" "topo_lvm_init" {
  name             = "topo-lvm-init"
  chart            = "https://github.com/lvm-init-for-k8s/lvm-init-for-k8s/releases/download/v1.2.0/lvm-init-for-k8s-1.2.0.tgz"
  namespace        = "kube-system"
  create_namespace = false
  wait             = "false"
  version          = "1.2.0"

  values = [
    file(join("/", [path.module, "helm_values", "topo_lvm_init.yaml"]))
  ]
}

# Topo LVM Controller Install
resource "helm_release" "topo_lvm_sc" {
  name             = "topo-lvm-sc"
  repository       = "https://topolvm.github.io/topolvm"
  chart            = "topolvm"
  namespace        = "kube-system"
  create_namespace = false
  wait             = "false"
  version          = "14.1.2"

  values = [
    file(join("/", [path.module, "helm_values", "topo_lvm_sc.yaml"]))
  ]

  depends_on = [kubernetes_manifest.letsencrypt_cluster_issuer, helm_release.topo_lvm_init]
}