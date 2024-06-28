# Namespace for the LogScale and Kubernetes cluster
resource "kubernetes_namespace" "logscale" {
  metadata {
    name = var.logscale_cluster_k8s_namespace_name
  }
}

# Helm release for the Humio Operator
resource "helm_release" "humio_operator" {
  count        = var.humio_operator_enabled ? 1 : 0
  name         = "humio-operator"
  repository   = "https://humio.github.io/humio-operator"
  chart        = "humio-operator"
  namespace    = kubernetes_namespace.logscale.metadata.0.name
  wait         = "false"
  version      = var.humio_operator_chart_version
  skip_crds    = true
  reset_values = true

  set {
    name  = "operator.image.tag"
    value = var.humio_operator_version
  }

  dynamic "set" {
    for_each = [for key, value in var.humio_operator_extra_values : {
      helm_variable_name  = key
      helm_variable_value = value
    } if length(value) > 0]
    content {
      name  = set.value.helm_variable_name
      value = set.value.helm_variable_value
    }
  }

  depends_on = [
    null_resource.wait_for_humio_operator_crds,
  ]
}

# Humio Operator CRD install
resource "null_resource" "humio_operator_crds" {
  count = var.humio_operator_enabled ? 1 : 0
  provisioner "local-exec" {
    command = "kubectl apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioclusters.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioexternalclusters.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl  apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioingesttokens.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl  apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioparsers.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humiorepositories.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl  apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioviews.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl  apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioalerts.yaml"
  }

  provisioner "local-exec" {
    command = "kubectl  apply --server-side -f https://raw.githubusercontent.com/humio/humio-operator/humio-operator-${var.humio_operator_version}/config/crd/bases/core.humio.com_humioactions.yaml"
  }

  triggers = {
    operator_crd_path = var.humio_operator_version
  }

}

# Wait for Humio Operator CRD install
resource "null_resource" "wait_for_humio_operator_crds" {
  provisioner "local-exec" {
    command = "sleep 5"
  }
  depends_on = [null_resource.humio_operator_crds]
}

# Create a secret for the Humio license
resource "kubernetes_secret" "humiocluster_license" {
  metadata {
    name      = "${local.logscale_cluster_name}-license"
    namespace = "logging"
  }
  data = {
    humio-license-key = var.humiocluster_license
  }
}

# Create a random key for encrypting data in bucket storage
resource "random_password" "gcp-storage-encryption-password" {
  length  = 64
  special = false
}

# Create an encryption key for the data stored in GCP
resource "kubernetes_secret" "GCP_STORAGE_ENCRYPTION_KEY" {
  metadata {
    name      = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
    namespace = kubernetes_namespace.logscale.id
  }
  data = {
    gcp-storage-encryption-key = random_password.gcp-storage-encryption-password.result
  }
}

# Create an encryption key for the data stored in GCP
resource "random_password" "static_admin_password" {
  length  = 18
  special = false
}

# Create a secret for the admin user
resource "kubernetes_secret" "static_user_logins" {
  metadata {
    name      = "${local.logscale_cluster_name}-static-users"
    namespace = "logging"
  }
  data = {
    users = "admin:${random_password.static_admin_password.result}"
  }
}


locals {
  kafka_cmd = <<-EOT
            trap "echo SIGINT; [[ $pid ]] && kill $pid; exit" SIGINT
            trap "echo SIGTERM; [[ $pid ]] && kill $pid; exit" SIGTERM
            cat <<EOF > /tmp/kafka-client/kafka.properties
            security.protocol=SSL
            ssl.truststore.type=PKCS12
            ssl.truststore.password=$SECRET_KEY
            ssl.truststore.location=/tmp/kafka/ca.p12
            EOF
            while true; do sleep 10; done;
            EOT
}


# Basic cluster type LogScale cluster specification
resource "kubernetes_manifest" "humio_cluster_type_basic" {
  count = contains(["basic"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "core.humio.com/v1alpha1"
    "kind"       = "HumioCluster"
    "metadata" = {
      "name"      = "${local.logscale_cluster_name}"
      "namespace" = "${kubernetes_namespace.logscale.id}"
    }
    "spec" = {
      "nodeCount" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_node_count"]
      "affinity" = {
        "nodeAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = {
            "nodeSelectorTerms" = [
              {
                "matchExpressions" = [
                  {
                    "key"      = "kubernetes.io/arch"
                    "operator" = "In"
                    "values" = [
                      "amd64",
                    ]
                  },
                  {
                    "key"      = "kubernetes.io/os"
                    "operator" = "In"
                    "values" = [
                      "linux",
                    ]
                  },
                  {
                    "key"      = "k8s-app"
                    "operator" = "In"
                    "values" = [
                      "logscale-${local.logscale_cluster_identifier}",
                    ]
                  },
                  {
                    "key"      = "storageclass"
                    "operator" = "In"
                    "values" = [
                      "nvme",
                    ]
                  },
                ]
              },
            ]
          }
        }
        "podAntiAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = [
            {
              "labelSelector" = {
                "matchExpressions" = [
                  {
                    "key"      = "app.kubernetes.io/name"
                    "operator" = "In"
                    "values" = [
                      "humio",
                    ]
                  },
                ]
              }
              "topologyKey" = "kubernetes.io/hostname"
            },
          ]
        }
      }
      "dataVolumePersistentVolumeClaimSpecTemplate" = {
        "accessModes" = [
          "ReadWriteOnce",
        ]
        "resources" = {
          "requests" = {
            "storage" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_data_disk_size"]
          }
        }
        "storageClassName" = "topolvm-provisioner"
      }
      "digestPartitionsCount" = 840
      "environmentVariables" = [
        {
          "name"  = "AUTHENTICATION_METHOD"
          "value" = "static"
        },
        {
          "name" = "STATIC_USERS"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"  = "users"
              "name" = "${local.logscale_cluster_name}-static-users"
            }
          }
        },
        {
          "name"  = "EXTRA_KAFKA_CONFIGS_FILE"
          "value" = "/tmp/kafka-client/kafka.properties"
        },
        {
          "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
          "value" = "true"
        },
        {
          "name"  = "GCP_STORAGE_BUCKET"
          "value" = "${local.logscale_bucket_storage}"
        },
        {
          "name" = "GCP_STORAGE_ENCRYPTION_KEY"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"  = "gcp-storage-encryption-key"
              "name" = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
            }
          }
        },
        {
          "name"  = "USING_EPHEMERAL_DISKS"
          "value" = "true"
        },
        {
          "name"  = "KAFKA_SERVERS"
          "value" = "${local.logscale_cluster_name}-strimzi-kafka-kafka-bootstrap.logging.svc.cluster.local:9093"
        },
      ]
      "extraHumioVolumeMounts" = [
        {
          "mountPath" = "/tmp/kafka/"
          "name"      = "trust-store"
          "readOnly"  = true
        },
        {
          "mountPath" = "/tmp/kafka-client/"
          "name"      = "shared-volume"
          "readOnly"  = true
        },
      ]
      "extraVolumes" = [
        {
          "name" = "trust-store"
          "secret" = {
            "secretName" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
          }
        },
        {
          "emptyDir" = {}
          "name"     = "shared-volume"
        },
      ]
      "hostname" = "${var.public_url}"
      "humioServiceAccountAnnotations" = {
        "iam.gke.io/gcp-service-account" = "${local.logscale_cluster_name}-wl-identity@${var.project_id}.iam.gserviceaccount.com"
      }
      "image" = "humio/humio-core:1.131.1"
      "license" = {
        "secretKeyRef" = {
          "key"  = "humio-license-key"
          "name" = "${local.logscale_cluster_name}-license"
        }
      }
      "resources" = {
        "limits" = {
          "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["limits"]["cpu"],
          "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["limits"]["memory"]
        }
        "requests" = {
          "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["requests"]["cpu"],
          "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["requests"]["memory"]
        }
      }
      "sidecarContainer" = [
        {
          "args" = [
            "-c",
            local.kafka_cmd
          ]
          "command" = [
            "/bin/sh",
          ]
          "env" = [
            {
              "name" = "SECRET_KEY"
              "valueFrom" = {
                "secretKeyRef" = {
                  "key"  = "ca.password"
                  "name" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                }
              }
            },
          ]
          "image" = "alpine:3.18.4"
          "name"  = "kafka-config-sidecar"
          "volumeMounts" = [
            {
              "mountPath" = "/tmp/kafka-client"
              "name"      = "shared-volume"
            },
          ]
        },
      ]
      "targetReplicationFactor" = 2
      "tls" = {
        "enabled" = true
      }
    }
  }
  depends_on = [
    null_resource.wait_for_humio_operator_crds,
    kubernetes_manifest.logscale_kafka_cluster,
    helm_release.cert-manager,
    helm_release.topo_lvm_init,
    helm_release.topo_lvm_sc,
  ]
  computed_fields = ["metadata.labels"]

  field_manager {
    name            = "tfapply"
    force_conflicts = true
  }

}

# Ingress cluster type LogScale cluster specification
resource "kubernetes_manifest" "humio_cluster_type_ingress" {
  count = contains(["ingress"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "core.humio.com/v1alpha1"
    "kind"       = "HumioCluster"
    "metadata" = {
      "name"      = "${local.logscale_cluster_name}"
      "namespace" = "${kubernetes_namespace.logscale.id}"
    }
    "spec" = {
      "affinity" = {
        "nodeAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = {
            "nodeSelectorTerms" = [
              {
                "matchExpressions" = [
                  {
                    "key"      = "kubernetes.io/arch"
                    "operator" = "In"
                    "values" = [
                      "amd64",
                    ]
                  },
                  {
                    "key"      = "kubernetes.io/os"
                    "operator" = "In"
                    "values" = [
                      "linux",
                    ]
                  },
                  {
                    "key"      = "k8s-app"
                    "operator" = "In"
                    "values" = [
                      "logscale-${local.logscale_cluster_identifier}",
                    ]
                  },
                ]
              },
            ]
          }
        }
        "podAntiAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = [
            {
              "labelSelector" = {
                "matchExpressions" = [
                  {
                    "key"      = "app.kubernetes.io/name"
                    "operator" = "In"
                    "values" = [
                      "humio",
                    ]
                  },
                ]
              }
              "topologyKey" = "kubernetes.io/hostname"
            },
          ]
        }
      }
      "resources" = {
        "limits" = {
          "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["limits"]["cpu"],
          "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["limits"]["memory"]
        }
        "requests" = {
          "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["requests"]["cpu"],
          "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["requests"]["memory"]
        }
      }
      "dataVolumePersistentVolumeClaimSpecTemplate" = {
        "accessModes" = [
          "ReadWriteOnce",
        ]
        "resources" = {
          "requests" = {
            "storage" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_data_disk_size"]
          }
        }
        "storageClassName" = "topolvm-provisioner"
      }
      "digestPartitionsCount" = 840
      "environmentVariables" = [
        {
          "name"  = "AUTHENTICATION_METHOD"
          "value" = "static"
        },
        {
          "name" = "STATIC_USERS"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"  = "users"
              "name" = "${local.logscale_cluster_name}-static-users"
            }
          }
        },
        {
          "name"  = "EXTRA_KAFKA_CONFIGS_FILE"
          "value" = "/tmp/kafka-client/kafka.properties"
        },
        {
          "name"  = "USING_EPHEMERAL_DISKS"
          "value" = "true"
        },
        {
          "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
          "value" = "true"
        },
        {
          "name"  = "GCP_STORAGE_BUCKET"
          "value" = "${local.logscale_bucket_storage}"
        },
        {
          "name" = "GCP_STORAGE_ENCRYPTION_KEY"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"  = "gcp-storage-encryption-key"
              "name" = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
            }
          }
        },
        {
          "name"  = "KAFKA_SERVERS"
          "value" = "${local.logscale_cluster_name}-strimzi-kafka-kafka-bootstrap.logging.svc.cluster.local:9093"
        },
      ]
      "extraHumioVolumeMounts" = [
        {
          "mountPath" = "/tmp/kafka/"
          "name"      = "trust-store"
          "readOnly"  = true
        },
        {
          "mountPath" = "/tmp/kafka-client/"
          "name"      = "shared-volume"
          "readOnly"  = true
        },
      ]
      "extraVolumes" = [
        {
          "name" = "trust-store"
          "secret" = {
            "secretName" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
          }
        },
        {
          "emptyDir" = {}
          "name"     = "shared-volume"
        },
      ]
      "hostname" = "${var.public_url}"
      "humioServiceAccountAnnotations" = {
        "iam.gke.io/gcp-service-account" = "${local.logscale_cluster_name}-wl-identity@${var.project_id}.iam.gserviceaccount.com"
      }
      "image" = "humio/humio-core:1.131.1"
      "ingress" = {
        "enabled" = false
      }
      "license" = {
        "secretKeyRef" = {
          "key"  = "humio-license-key"
          "name" = "${local.logscale_cluster_name}-license"
        }
      }
      "nodeCount" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_node_count"]
      "nodePools" = [
        {
          "name" = "ingress-only"
          "spec" = {
            "nodeCount" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingress_node_count"]
            "affinity" = {
              "nodeAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = {
                  "nodeSelectorTerms" = [
                    {
                      "matchExpressions" = [
                        {
                          "key"      = "kubernetes.io/arch"
                          "operator" = "In"
                          "values" = [
                            "amd64",
                          ]
                        },
                        {
                          "key"      = "kubernetes.io/os"
                          "operator" = "In"
                          "values" = [
                            "linux",
                          ]
                        },
                        {
                          "key"      = "k8s-app"
                          "operator" = "In"
                          "values" = [
                            "logscale-ingress-${local.logscale_cluster_identifier}",
                          ]
                        },
                      ]
                    },
                  ]
                }
              }
              "podAntiAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = [
                  {
                    "labelSelector" = {
                      "matchExpressions" = [
                        {
                          "key"      = "app.kubernetes.io/name"
                          "operator" = "In"
                          "values" = [
                            "humio",
                          ]
                        },
                      ]
                    }
                    "topologyKey" = "kubernetes.io/hostname"
                  },
                ]
              }
            }
            "dataVolumePersistentVolumeClaimSpecTemplate" = {
              "accessModes" = [
                "ReadWriteOnce",
              ]
              "resources" = {
                "requests" = {
                  "storage" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingress_data_disk_size"]
                }
              }
              "storageClassName" = "standard-rwo"
            }
            "environmentVariables" = [
              {
                "name"  = "AUTHENTICATION_METHOD"
                "value" = "static"
              },
              {
                "name" = "STATIC_USERS"
                "valueFrom" = {
                  "secretKeyRef" = {
                    "key"  = "users"
                    "name" = "${local.logscale_cluster_name}-static-users"
                  }
                }
              },
              {
                "name"  = "NODE_ROLES"
                "value" = "httponly"
              },
              {
                "name"  = "QUERY_COORDINATOR"
                "value" = "false"
              },
              {
                "name"  = "EXTRA_KAFKA_CONFIGS_FILE"
                "value" = "/tmp/kafka-client/kafka.properties"
              },
              {
                "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
                "value" = "true"
              },
              {
                "name"  = "GCP_STORAGE_BUCKET"
                "value" = "${local.logscale_bucket_storage}"
              },
              {
                "name" = "GCP_STORAGE_ENCRYPTION_KEY"
                "valueFrom" = {
                  "secretKeyRef" = {
                    "key"  = "gcp-storage-encryption-key"
                    "name" = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
                  }
                }
              },
              {
                "name"  = "KAFKA_SERVERS"
                "value" = "${local.logscale_cluster_name}-strimzi-kafka-kafka-bootstrap.logging.svc.cluster.local:9093"
              },
            ]
            "extraHumioVolumeMounts" = [
              {
                "mountPath" = "/tmp/kafka/"
                "name"      = "trust-store"
                "readOnly"  = true
              },
              {
                "mountPath" = "/tmp/kafka-client/"
                "name"      = "shared-volume"
                "readOnly"  = true
              },
            ]
            "extraVolumes" = [
              {
                "name" = "trust-store"
                "secret" = {
                  "secretName" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                }
              },
              {
                "emptyDir" = {}
                "name"     = "shared-volume"
              },
            ]
            "humioServiceAccountAnnotations" = {
              "iam.gke.io/gcp-service-account" = "${local.logscale_cluster_name}-wl-identity@${var.project_id}.iam.gserviceaccount.com"
            }
            "image" = "humio/humio-core:1.131.1"
            "resources" = {
              "limits" = {
                "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingress_resources"]["limits"]["cpu"],
                "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingress_resources"]["limits"]["memory"]
              }
              "requests" = {
                "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingress_resources"]["requests"]["cpu"],
                "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingress_resources"]["requests"]["memory"]
              }
            }
            "sidecarContainer" = [
              {
                "args" = [
                  "-c",
                  local.kafka_cmd
                ]
                "command" = [
                  "/bin/sh",
                ]
                "env" = [
                  {
                    "name" = "SECRET_KEY"
                    "valueFrom" = {
                      "secretKeyRef" = {
                        "key"  = "ca.password"
                        "name" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                      }
                    }
                  },
                ]
                "image" = "alpine:3.18.4"
                "name"  = "kafka-config-sidecar"
                "volumeMounts" = [
                  {
                    "mountPath" = "/tmp/kafka-client"
                    "name"      = "shared-volume"
                  },
                ]
              },
            ]
            "updateStrategy" = {
              "type" = "RollingUpdate"
            }
          }
        },
      ]
      "nodeUUIDPrefix" = "/logscale_ingest"
      "resources" = {
        "requests" = {
          "cpu"    = 1
          "memory" = "2Gi"
        }
      }
      "sidecarContainer" = [
        {
          "args" = [
            "-c",
            local.kafka_cmd

          ]
          "command" = [
            "/bin/sh",
          ]
          "env" = [
            {
              "name" = "SECRET_KEY"
              "valueFrom" = {
                "secretKeyRef" = {
                  "key"  = "ca.password"
                  "name" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                }
              }
            },
          ]
          "image" = "alpine:3.18.4"
          "name"  = "kafka-config-sidecar"
          "volumeMounts" = [
            {
              "mountPath" = "/tmp/kafka-client"
              "name"      = "shared-volume"
            },
          ]
        },
      ]
      "targetReplicationFactor" = 2
      "tls" = {
        "enabled" = true
      }
    }

  }
  depends_on = [
    null_resource.wait_for_humio_operator_crds,
    kubernetes_manifest.logscale_kafka_cluster,
    helm_release.cert-manager,
    helm_release.topo_lvm_init,
    helm_release.topo_lvm_sc,
  ]
  field_manager {
    name            = "tfapply"
    force_conflicts = true
  }
}

# Internal-ingest cluster type LogScale cluster specification
resource "kubernetes_manifest" "humio_cluster_type_internal_ingest" {
  count = contains(["internal-ingest"], var.logscale_cluster_type) ? 1 : 0
  manifest = {
    "apiVersion" = "core.humio.com/v1alpha1"
    "kind"       = "HumioCluster"
    "metadata" = {
      "name"      = "${local.logscale_cluster_name}"
      "namespace" = "${kubernetes_namespace.logscale.id}"
    }
    "spec" = {
      "resources" = {
        "limits" = {
          "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["limits"]["cpu"],
          "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["limits"]["memory"]
        }
        "requests" = {
          "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["requests"]["cpu"],
          "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_resources"]["requests"]["memory"]
        }
      }
      "affinity" = {
        "nodeAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = {
            "nodeSelectorTerms" = [
              {
                "matchExpressions" = [
                  {
                    "key"      = "kubernetes.io/arch"
                    "operator" = "In"
                    "values" = [
                      "amd64",
                    ]
                  },
                  {
                    "key"      = "kubernetes.io/os"
                    "operator" = "In"
                    "values" = [
                      "linux",
                    ]
                  },
                  {
                    "key"      = "k8s-app"
                    "operator" = "In"
                    "values" = [
                      "logscale",
                      "logscale-${local.logscale_cluster_identifier}",
                    ]
                  },
                  {
                    "key"      = "storageclass"
                    "operator" = "In"
                    "values" = [
                      "nvme",
                    ]
                  },
                ]
              },
            ]
          }
        }
        "podAntiAffinity" = {
          "requiredDuringSchedulingIgnoredDuringExecution" = [
            {
              "labelSelector" = {
                "matchExpressions" = [
                  {
                    "key"      = "app.kubernetes.io/name"
                    "operator" = "In"
                    "values" = [
                      "humio",
                    ]
                  },
                ]
              }
              "topologyKey" = "kubernetes.io/hostname"
            },
          ]
        }
      }
      "dataVolumePersistentVolumeClaimSpecTemplate" = {
        "accessModes" = [
          "ReadWriteOnce",
        ]
        "resources" = {
          "requests" = {
            "storage" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_data_disk_size"]
          }
        }
        "storageClassName" = "topolvm-provisioner"
      }
      "digestPartitionsCount" = 840
      "environmentVariables" = [
        {
          "name"  = "AUTHENTICATION_METHOD"
          "value" = "static"
        },
        {
          "name" = "STATIC_USERS"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"  = "users"
              "name" = "${local.logscale_cluster_name}-static-users"
            }
          }
        },
        {
          "name"  = "EXTRA_KAFKA_CONFIGS_FILE"
          "value" = "/tmp/kafka-client/kafka.properties"
        },
        {
          "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
          "value" = "true"
        },
        {
          "name"  = "GCP_STORAGE_BUCKET"
          "value" = "${local.logscale_bucket_storage}"
        },
        {
          "name" = "GCP_STORAGE_ENCRYPTION_KEY"
          "valueFrom" = {
            "secretKeyRef" = {
              "key"  = "gcp-storage-encryption-key"
              "name" = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
            }
          }
        },
        {
          "name"  = "USING_EPHEMERAL_DISKS"
          "value" = "true"
        },
        {
          "name"  = "KAFKA_SERVERS"
          "value" = "${local.logscale_cluster_name}-strimzi-kafka-kafka-bootstrap.logging.svc.cluster.local:9093"
        },
      ]
      "extraHumioVolumeMounts" = [
        {
          "mountPath" = "/tmp/kafka/"
          "name"      = "trust-store"
          "readOnly"  = true
        },
        {
          "mountPath" = "/tmp/kafka-client/"
          "name"      = "shared-volume"
          "readOnly"  = true
        },
      ]
      "extraVolumes" = [
        {
          "name" = "trust-store"
          "secret" = {
            "secretName" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
          }
        },
        {
          "emptyDir" = {}
          "name"     = "shared-volume"
        },
      ]
      "hostname" = "${var.public_url}"
      "humioServiceAccountAnnotations" = {
        "iam.gke.io/gcp-service-account" = "${local.logscale_cluster_name}-wl-identity@${var.project_id}.iam.gserviceaccount.com"
      }
      "image" = "humio/humio-core:1.131.1"
      "ingress" = {
        "enabled" = false
      }
      "license" = {
        "secretKeyRef" = {
          "key"  = "humio-license-key"
          "name" = "${local.logscale_cluster_name}-license"
        }
      }
      "nodeCount" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_digest_node_count"]
      "nodePools" = [
        {
          "name" = "ingest-only"
          "spec" = {
            "resources" = {
              "limits" = {
                "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingest_resources"]["limits"]["cpu"],
                "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingest_resources"]["limits"]["memory"]
              }
              "requests" = {
                "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingest_resources"]["requests"]["cpu"],
                "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingest_resources"]["requests"]["memory"]
              }
            }
            "affinity" = {
              "nodeAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = {
                  "nodeSelectorTerms" = [
                    {
                      "matchExpressions" = [
                        {
                          "key"      = "kubernetes.io/arch"
                          "operator" = "In"
                          "values" = [
                            "amd64",
                          ]
                        },
                        {
                          "key"      = "kubernetes.io/os"
                          "operator" = "In"
                          "values" = [
                            "linux",
                          ]
                        },
                        {
                          "key"      = "k8s-app"
                          "operator" = "In"
                          "values" = [
                            "logscale-ingest-${local.logscale_cluster_identifier}",
                          ]
                        },
                      ]
                    },
                  ]
                }
              }
              "podAntiAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = [
                  {
                    "labelSelector" = {
                      "matchExpressions" = [
                        {
                          "key"      = "app.kubernetes.io/name"
                          "operator" = "In"
                          "values" = [
                            "humio",
                          ]
                        },
                      ]
                    }
                    "topologyKey" = "kubernetes.io/hostname"
                  },
                ]
              }
            }
            "dataVolumePersistentVolumeClaimSpecTemplate" = {
              "accessModes" = [
                "ReadWriteOnce",
              ]
              "resources" = {
                "requests" = {
                  "storage" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingest_data_disk_size"]
                }
              }
              "storageClassName" = "standard-rwo"
            }
            "environmentVariables" = [
              {
                "name"  = "AUTHENTICATION_METHOD"
                "value" = "static"
              },
              {
                "name" = "STATIC_USERS"
                "valueFrom" = {
                  "secretKeyRef" = {
                    "key"  = "users"
                    "name" = "${local.logscale_cluster_name}-static-users"
                  }
                }
              },
              {
                "name"  = "NODE_ROLES"
                "value" = "ingestonly"
              },
              {
                "name"  = "QUERY_COORDINATOR"
                "value" = "false"
              },
              {
                "name"  = "EXTRA_KAFKA_CONFIGS_FILE"
                "value" = "/tmp/kafka-client/kafka.properties"
              },
              {
                "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
                "value" = "true"
              },
              {
                "name"  = "GCP_STORAGE_BUCKET"
                "value" = "${local.logscale_bucket_storage}"
              },
              {
                "name" = "GCP_STORAGE_ENCRYPTION_KEY"
                "valueFrom" = {
                  "secretKeyRef" = {
                    "key"  = "gcp-storage-encryption-key"
                    "name" = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
                  }
                }
              },
              {
                "name"  = "KAFKA_SERVERS"
                "value" = "${local.logscale_cluster_name}-strimzi-kafka-kafka-bootstrap.logging.svc.cluster.local:9093"
              },
            ]
            "extraHumioVolumeMounts" = [
              {
                "mountPath" = "/tmp/kafka/"
                "name"      = "trust-store"
                "readOnly"  = true
              },
              {
                "mountPath" = "/tmp/kafka-client/"
                "name"      = "shared-volume"
                "readOnly"  = true
              },
            ]
            "extraVolumes" = [
              {
                "name" = "trust-store"
                "secret" = {
                  "secretName" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                }
              },
              {
                "emptyDir" = {}
                "name"     = "shared-volume"
              },
            ]
            "humioServiceAccountAnnotations" = {
              "iam.gke.io/gcp-service-account" = "${local.logscale_cluster_name}-wl-identity@${var.project_id}.iam.gserviceaccount.com"
            }
            "image"     = "humio/humio-core:1.131.1"
            "nodeCount" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ingest_node_count"]
            "sidecarContainer" = [
              {
                "args" = [
                  "-c",
                  local.kafka_cmd
                ]
                "command" = [
                  "/bin/sh",
                ]
                "env" = [
                  {
                    "name" = "SECRET_KEY"
                    "valueFrom" = {
                      "secretKeyRef" = {
                        "key"  = "ca.password"
                        "name" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                      }
                    }
                  },
                ]
                "image" = "alpine:3.18.4"
                "name"  = "kafka-config-sidecar"
                "volumeMounts" = [
                  {
                    "mountPath" = "/tmp/kafka-client"
                    "name"      = "shared-volume"
                  },
                ]
              },
            ]
            "updateStrategy" = {
              "type" = "RollingUpdate"
            }
          }
        },
        {
          "name" = "ui-only"
          "spec" = {
            "affinity" = {
              "nodeAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = {
                  "nodeSelectorTerms" = [
                    {
                      "matchExpressions" = [
                        {
                          "key"      = "kubernetes.io/arch"
                          "operator" = "In"
                          "values" = [
                            "amd64",
                          ]
                        },
                        {
                          "key"      = "kubernetes.io/os"
                          "operator" = "In"
                          "values" = [
                            "linux",
                          ]
                        },
                        {
                          "key"      = "k8s-app"
                          "operator" = "In"
                          "values" = [
                            "logscale-ui-${local.logscale_cluster_identifier}",
                          ]
                        },
                      ]
                    },
                  ]
                }
              }
              "podAntiAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = [
                  {
                    "labelSelector" = {
                      "matchExpressions" = [
                        {
                          "key"      = "app.kubernetes.io/name"
                          "operator" = "In"
                          "values" = [
                            "humio",
                          ]
                        },
                      ]
                    }
                    "topologyKey" = "kubernetes.io/hostname"
                  },
                ]
              }
            }
            "dataVolumePersistentVolumeClaimSpecTemplate" = {
              "accessModes" = [
                "ReadWriteOnce",
              ]
              "resources" = {
                "requests" = {
                  "storage" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ui_data_disk_size"]
                }
              }
              "storageClassName" = "standard-rwo"
            }
            "environmentVariables" = [
              {
                "name"  = "AUTHENTICATION_METHOD"
                "value" = "static"
              },
              {
                "name" = "STATIC_USERS"
                "valueFrom" = {
                  "secretKeyRef" = {
                    "key"  = "users"
                    "name" = "${local.logscale_cluster_name}-static-users"
                  }
                }
              },
              {
                "name"  = "NODE_ROLES"
                "value" = "httponly"
              },
              {
                "name"  = "EXTRA_KAFKA_CONFIGS_FILE"
                "value" = "/tmp/kafka-client/kafka.properties"
              },
              {
                "name"  = "QUERY_COORDINATOR"
                "value" = "false"
              },
              {
                "name"  = "GCP_STORAGE_WORKLOAD_IDENTITY"
                "value" = "true"
              },
              {
                "name"  = "GCP_STORAGE_BUCKET"
                "value" = "${local.logscale_bucket_storage}"
              },
              {
                "name" = "GCP_STORAGE_ENCRYPTION_KEY"
                "valueFrom" = {
                  "secretKeyRef" = {
                    "key"  = "gcp-storage-encryption-key"
                    "name" = "${local.logscale_cluster_name}-gcp-storage-encryption-key"
                  }
                }
              },
              {
                "name"  = "KAFKA_SERVERS"
                "value" = "${local.logscale_cluster_name}-strimzi-kafka-kafka-bootstrap.logging.svc.cluster.local:9093"
              },
            ]
            "extraHumioVolumeMounts" = [
              {
                "mountPath" = "/tmp/kafka/"
                "name"      = "trust-store"
                "readOnly"  = true
              },
              {
                "mountPath" = "/tmp/kafka-client/"
                "name"      = "shared-volume"
                "readOnly"  = true
              },
            ]
            "extraVolumes" = [
              {
                "name" = "trust-store"
                "secret" = {
                  "secretName" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                }
              },
              {
                "emptyDir" = {}
                "name"     = "shared-volume"
              },
            ]
            "humioServiceAccountAnnotations" = {
              "iam.gke.io/gcp-service-account" = "${local.logscale_cluster_name}-wl-identity@${var.project_id}.iam.gserviceaccount.com"
            }
            "image"     = "humio/humio-core:1.131.1"
            "nodeCount" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ui_node_count"]
            "resources" = {
              "limits" = {
                "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ui_resources"]["limits"]["cpu"],
                "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ui_resources"]["limits"]["memory"]
              }
              "requests" = {
                "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ui_resources"]["requests"]["cpu"],
                "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["logscale_ui_resources"]["requests"]["memory"]
              }
            }
            "sidecarContainer" = [
              {
                "args" = [
                  "-c",
                  local.kafka_cmd
                ]
                "command" = [
                  "/bin/sh",
                ]
                "env" = [
                  {
                    "name" = "SECRET_KEY"
                    "valueFrom" = {
                      "secretKeyRef" = {
                        "key"  = "ca.password"
                        "name" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                      }
                    }
                  },
                ]
                "image" = "alpine:3.18.4"
                "name"  = "kafka-config-sidecar"
                "volumeMounts" = [
                  {
                    "mountPath" = "/tmp/kafka-client"
                    "name"      = "shared-volume"
                  },
                ]
              },
            ]
            "updateStrategy" = {
              "type" = "RollingUpdate"
            }
          }
        },
      ]
      "nodeUUIDPrefix" = "/logscale_digest"
      "resources" = {
        "requests" = {
          "cpu"    = 1
          "memory" = "2Gi"
        }
      }
      "sidecarContainer" = [
        {
          "args" = [
            "-c",
            local.kafka_cmd
          ]
          "command" = [
            "/bin/sh",
          ]
          "env" = [
            {
              "name" = "SECRET_KEY"
              "valueFrom" = {
                "secretKeyRef" = {
                  "key"  = "ca.password"
                  "name" = "${local.logscale_cluster_name}-strimzi-kafka-cluster-ca-cert"
                }
              }
            },
          ]
          "image" = "alpine:3.18.4"
          "name"  = "kafka-config-sidecar"
          "volumeMounts" = [
            {
              "mountPath" = "/tmp/kafka-client"
              "name"      = "shared-volume"
            },
          ]
        },
      ]
      "targetReplicationFactor" = 2
      "tls" = {
        "enabled" = true
      }
    }
  }
  depends_on = [
    null_resource.wait_for_humio_operator_crds,
    kubernetes_manifest.logscale_kafka_cluster,
    helm_release.cert-manager,
    helm_release.topo_lvm_init,
    helm_release.topo_lvm_sc,
  ]

  field_manager {
    name            = "tfapply"
    force_conflicts = true
  }
}