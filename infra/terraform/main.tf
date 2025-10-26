# infra/terraform/main.tf
terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.95"
    }
  }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = "ru-central1-a"
}

# Сеть и подсеть
resource "yandex_vpc_network" "k8s-net" {
  name = "k8s-network"
}

resource "yandex_vpc_subnet" "k8s-subnet" {
  name           = "k8s-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.k8s-net.id
  v4_cidr_blocks = ["10.10.0.0/16"]
}

# Сервисные аккаунты
resource "yandex_iam_service_account" "k8s-sa" {
  name = "k8s-service-account"
}

resource "yandex_iam_service_account" "k8s-node-sa" {
  name = "k8s-node-service-account"
}

# Роли для аккаунтов
resource "yandex_resourcemanager_folder_iam_member" "k8s_sa_editor" {
  folder_id = var.yc_folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_node_sa_puller" {
  folder_id = var.yc_folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-node-sa.id}"
}

# Kubernetes-кластер
resource "yandex_kubernetes_cluster" "webbooks-k8s" {
  name        = "webbooks-k8s"
  description = "K8s cluster for WebBooks DevOps project"

  network_id = yandex_vpc_network.k8s-net.id

  master {
    version = "1.28"
    zonal {
      zone      = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.k8s-subnet.id
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.k8s-sa.id
  node_service_account_id = yandex_iam_service_account.k8s-node-sa.id

  release_channel = "RAPID"

  dynamic "maintenance_policy" {
    for_each = [{}]
    content {
      auto_upgrade = true
    }
  }

  master_logging {
    enabled = true
  }
}
