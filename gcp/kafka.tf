# deploy Kafka and Zookeeper using Strimzi operator

# Helm for Strimzi
resource "helm_release" "strimzi_operator" {
  name       = "strimzi-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  namespace  = kubernetes_namespace.logscale.id
  wait       = "false"
  version    = var.strimzi_operator_chart_version
}

# Rebalance setup for Strimzi Kafka
resource "kubernetes_manifest" "logscale_kafka_cluster_rebalance" {
  manifest = {
    "apiVersion" = "kafka.strimzi.io/v1beta2"
    "kind"       = "KafkaRebalance"
    "metadata" = {
      "labels" = {
        "strimzi.io/cluster" = "${local.logscale_cluster_name}-strimzi-kafka"
      }
      "name"      = "${local.logscale_cluster_name}-strimzi-kafka-rebalance"
      "namespace" = kubernetes_namespace.logscale.id
    }
    "spec" = {
      "goals" = [
        "NetworkInboundCapacityGoal",
        "DiskCapacityGoal",
        "RackAwareGoal",
        "NetworkOutboundCapacityGoal",
        "CpuCapacityGoal",
        "ReplicaCapacityGoal",
      ]
    }
  }
  depends_on = [
    helm_release.strimzi_operator,
  ]
}

# Kafka cluster specificiation
resource "kubernetes_manifest" "logscale_kafka_cluster" {
  manifest = {
    "apiVersion" = "kafka.strimzi.io/v1beta2"
    "kind"       = "Kafka"
    "metadata" = {
      "name"      = "${local.logscale_cluster_name}-strimzi-kafka"
      "namespace" = kubernetes_namespace.logscale.id
    }
    "spec" = {
      "kafka" = {
        "config" = {
          "auto.create.topics.enable"                = true
          "default.replication.factor"               = 3
          "min.insync.replicas"                      = 2
          "offsets.topic.replication.factor"         = 2
          "replica.selector.class"                   = "org.apache.kafka.common.replica.RackAwareReplicaSelector"
          "ssl.client.auth"                          = "none"
          "transaction.state.log.min.isr"            = 1
          "transaction.state.log.replication.factor" = 2
        }
        "listeners" = [
          {
            "name" = "plain"
            "port" = 9092
            "tls"  = false
            "type" = "internal"
          },
          {
            "name" = "tls"
            "port" = 9093
            "tls"  = true
            "type" = "internal"
          },
        ]
        "rack" = {
          "topologyKey" = "topology.kubernetes.io/zone"
        }
        "replicas" = local.logscale_cluster_definitions[local.logscale_cluster_size]["kafka_broker_node_count"]
        "resources" = {
          "limits" = {
            "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["kafka_broker_resources"]["limits"]["cpu"],
            "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["kafka_broker_resources"]["limits"]["memory"]
          }
          "requests" = {
            "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["kafka_broker_resources"]["requests"]["cpu"],
            "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["kafka_broker_resources"]["requests"]["memory"]
          }
        }
        "storage" = {
          "deleteClaim" = true
          "size"        = local.logscale_cluster_definitions[local.logscale_cluster_size]["kafka_broker_data_disk_size"]
          "type"        = "persistent-claim"
        }
        "template" = {
          "pod" = {
            "affinity" = {
              "nodeAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = {
                  "nodeSelectorTerms" = [
                    {
                      "matchExpressions" = [
                        {
                          "key"      = "k8s-app"
                          "operator" = "In"
                          "values" = [
                            "kafka-${local.logscale_cluster_identifier}",
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
                            "kafka", "zookeeper"
                          ]
                        },
                      ]
                    }
                    "topologyKey" = "kubernetes.io/hostname"
                  },
                ]
              }
            }
          }
        }
        "version" = "3.4.0"
      }
      "zookeeper" = {
        "replicas" = local.logscale_cluster_definitions[local.logscale_cluster_size]["zookeeper_node_count"]
        "resources" = {
          "limits" = {
            "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["zookeeper_resources"]["limits"]["cpu"],
            "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["zookeeper_resources"]["limits"]["memory"]
          }
          "requests" = {
            "cpu"    = local.logscale_cluster_definitions[local.logscale_cluster_size]["zookeeper_resources"]["requests"]["cpu"],
            "memory" = local.logscale_cluster_definitions[local.logscale_cluster_size]["zookeeper_resources"]["requests"]["memory"]
          }
        }
        "storage" = {
          "deleteClaim" = true
          "size"        = local.logscale_cluster_definitions[local.logscale_cluster_size]["zookeeper_data_disk_size"]
          "type"        = "persistent-claim"
        }
        "template" = {
          "pod" = {
            "affinity" = {
              "nodeAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = {
                  "nodeSelectorTerms" = [
                    {
                      "matchExpressions" = [
                        {
                          "key"      = "k8s-app"
                          "operator" = "In"
                          "values" = [
                            "zookeeper-${local.logscale_cluster_identifier}",
                          ]
                        },
                      ]
                    },
                  ]
                }
              },
              "podAntiAffinity" = {
                "requiredDuringSchedulingIgnoredDuringExecution" = [
                  {
                    "labelSelector" = {
                      "matchExpressions" = [
                        {
                          "key"      = "app.kubernetes.io/name"
                          "operator" = "In"
                          "values" = [
                            "kafka", "zookeeper"
                          ]
                        },
                      ]
                    }
                    "topologyKey" = "kubernetes.io/hostname"
                  },
                ]
              }
            }
          }
        }
      }
    }
  }
  depends_on = [
    helm_release.strimzi_operator,
    kubernetes_namespace.logscale
  ]
}
