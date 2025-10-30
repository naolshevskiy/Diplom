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

# Используем СУЩЕСТВУЮЩУЮ сеть (укажи её имя или ID)
data "yandex_vpc_network" "existing" {
  name = "default"  # ← замени, если имя другое (например, "network-abc123")
}

# Создаём подсеть внутри существующей сети
resource "yandex_vpc_subnet" "k8s-subnet" {
  name           = "k8s-subnet"
  zone           = "ru-central1-a"
  network_id     = data.yandex_vpc_network.existing.id
  v4_cidr_blocks = ["10.10.1.0/24"]
}

# Сервисные аккаунты
resource "yandex_iam_service_account" "k8s-sa" {
  name = "k8s-service-account"
}

resource "yandex_iam_service_account" "k8s-node-sa" {
  name = "k8s-node-service-account"
}

# Роли
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
  description = "K8s cluster for WebBooks"

  network_id = data.yandex_vpc_network.existing.id

  master {
    version = "1.30"
    zonal {
      zone      = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.k8s-subnet.id
    }
    public_ip = true

    maintenance_policy {
      auto_upgrade = true
    }

    master_logging {
      enabled = true
    }
  }

  service_account_id      = yandex_iam_service_account.k8s-sa.id
  node_service_account_id = yandex_iam_service_account.k8s-node-sa.id

  release_channel = "RAPID"
}

# Worker-ноды
resource "yandex_kubernetes_node_group" "webbooks-nodes" {
  cluster_id  = yandex_kubernetes_cluster.webbooks-k8s.id
  name        = "webbooks-nodes"
  description = "Node group for WebBooks app"

  instance_template {
    platform_id = "standard-v1"

    resources {
      memory = 2
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 20
    }

    scheduling_policy {
      preemptible = false
    }

    # Исправление: nat теперь внутри network_interface
    network_interface {
      subnet_ids = [yandex_vpc_subnet.k8s-subnet.id]  # ← явно указываем нашу подсеть
      nat        = true  # даёт выход в интернет
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }

  maintenance_policy {
    auto_repair  = true
    auto_upgrade = true
  }
}
