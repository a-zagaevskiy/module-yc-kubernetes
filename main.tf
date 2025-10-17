terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = var.yandex_zone
}

locals {
  cluster_name = "${var.cluster_name}-${var.env_name}"
}

# Yandex Kubernetes Cluster Resources
#  * Service Accounts for cluster and nodes
#  * IAM bindings for permissions
#  * Kubernetes Cluster
#

# Сервисный аккаунт для управления кластером
resource "yandex_iam_service_account" "k8s-cluster" {
  name        = local.cluster_name
  description = "Service account for Kubernetes cluster management"
}

# Роль редактора для сервисного аккаунта кластера
resource "yandex_resourcemanager_folder_iam_member" "k8s-cluster-editor" {
  # folder_id = var.yandex_folder_id
  role   = "editor"
  member = "serviceAccount:${yandex_iam_service_account.k8s-cluster.id}"
}

# Сервисный аккаунт для worker nodes
resource "yandex_iam_service_account" "k8s-nodes" {
  name        = "${local.cluster_name}-nodes"
  description = "Service account for Kubernetes worker nodes"
}

# Роли для сервисного аккаунта нод
resource "yandex_resourcemanager_folder_iam_member" "k8s-nodes-images-puller" {
  # folder_id = var.yandex_folder_id
  role   = "container-registry.images.puller"
  member = "serviceAccount:${yandex_iam_service_account.k8s-nodes.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-nodes-metrics-writer" {
  # folder_id = var.yandex_folder_id
  role   = "monitoring.metricsWriter"
  member = "serviceAccount:${yandex_iam_service_account.k8s-nodes.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-nodes-load-balancer-admin" {
  # folder_id = var.yandex_folder_id
  role   = "load-balancer.admin"
  member = "serviceAccount:${yandex_iam_service_account.k8s-nodes.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s-nodes-vpc-public-admin" {
  # folder_id = var.yandex_folder_id
  role   = "vpc.publicAdmin"
  member = "serviceAccount:${yandex_iam_service_account.k8s-nodes.id}"
}

# Security Group аналог - Network Policy и группы безопасности Yandex Cloud
resource "yandex_vpc_security_group" "k8s-cluster" {
  name        = local.cluster_name
  description = "Security group for Kubernetes cluster"
  network_id  = var.vpc_id

  # Ingress правила - аналогично AWS SG
  ingress {
    description    = "Inter-pod communication"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    description    = "Node and control plane communication"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress правила
  egress {
    description    = "Full outbound access"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Kubernetes Cluster
resource "yandex_kubernetes_cluster" "ms-up-running" {
  name       = local.cluster_name
  network_id = var.vpc_id

  service_account_id      = yandex_iam_service_account.k8s-cluster.id
  node_service_account_id = yandex_iam_service_account.k8s-nodes.id

  master {
    version = var.k8s_version
    regional {
      region = var.yandex_zone

      # Мастер ноды распределяются по подсетям
      dynamic "location" {
        for_each = var.cluster_subnet_ids
        content {
          subnet_id = location.value
          zone      = yandex_vpc_subnet.subnets[location.key].zone
        }
      }
    }

    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.k8s-cluster.id]
  }

  kms_provider {
    key_id = yandex_kms_symmetric_key.k8s-key.id
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s-cluster-editor,
    yandex_resourcemanager_folder_iam_member.k8s-nodes-images-puller,
    yandex_resourcemanager_folder_iam_member.k8s-nodes-metrics-writer,
    yandex_resourcemanager_folder_iam_member.k8s-nodes-load-balancer-admin,
    yandex_resourcemanager_folder_iam_member.k8s-nodes-vpc-public-admin
  ]
}

#
# Worker Nodes Resources
#  * Node Group для worker nodes
#

resource "yandex_kubernetes_node_group" "ms-node-group" {
  cluster_id  = yandex_kubernetes_cluster.ms-up-running.id
  name        = "microservices"
  description = "Microservices node group"

  instance_template {
    platform_id = "standard-v2"

    resources {
      memory = var.nodegroup_memory
      cores  = var.nodegroup_cores
    }

    boot_disk {
      type = "network-ssd"
      size = var.nodegroup_disk_size
    }

    scheduling_policy {
      preemptible = false
    }

    network_interface {
      subnet_ids         = var.nodegroup_subnet_ids
      security_group_ids = [yandex_vpc_security_group.k8s-cluster.id]
    }
  }

  scale_policy {
    auto_scale {
      min     = var.nodegroup_min_size
      max     = var.nodegroup_max_size
      initial = var.nodegroup_desired_size
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
    location {
      zone = "ru-central1-b"
    }
    location {
      zone = "ru-central1-c"
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
  }
}

# Создание kubeconfig файла
resource "local_file" "kubeconfig" {
  content = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_id   = yandex_kubernetes_cluster.ms-up-running.id
    cluster_name = local.cluster_name
    server       = yandex_kubernetes_cluster.ms-up-running.master[0].external_v4_endpoint
    ca_cert      = yandex_kubernetes_cluster.ms-up-running.master[0].cluster_ca_certificate
    token        = data.yandex_iam_service_account_key.k8s-key.service_account_key
  })
  filename = "kubeconfig_${local.cluster_name}"
}

# Ключ сервисного аккаунта для аутентификации
data "yandex_iam_service_account_key" "k8s-key" {
  service_account_id = yandex_iam_service_account.k8s-cluster.id
}

# Шаблон kubeconfig
# templates/kubeconfig.tpl
/*
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${ca_cert}
    server: ${server}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: ${cluster_name}
  name: ${cluster_name}
current-context: ${cluster_name}
kind: Config
preferences: {}
users:
- name: ${cluster_name}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: yc
      args:
      - k8s
      - create-token
*/