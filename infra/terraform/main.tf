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

# Используем СУЩЕСТВУЮЩУЮ сеть "default"
data "yandex_vpc_network" "default" {
  name = "default"
}

# --- УДАЛЯЕМ РУЧНУЮ ПОДСЕТЬ ---

resource "yandex_iam_service_account" "k8s-sa" {
  name = "k8s-service-account"
}

resource "yandex_iam_service_account" "k8s-node-sa" {
  name = "k8s-node-service-account"
}

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

# Кластер — без указания subnet_id (авто)
resource "yandex_kubernetes_cluster" "webbooks-k8s" {
  name        = "webbooks-k8s"
  network_id  = data.yandex_vpc_network.default.id  # только сеть

  master {
    version = "1.30"
    # --- НЕ УКАЗЫВАЕМ subnet_id → Yandex создаст сам ---
    zonal {
      zone = "ru-central1-a"
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
  release_channel         = "RAPID"
}

# Node group — без subnet_id
resource "yandex_kubernetes_node_group" "webbooks-nodes" {
  cluster_id = yandex_kubernetes_cluster.webbooks-k8s.id
  name       = "webbooks-nodes"

  instance_template {
    platform_id = "standard-v3"
    nat         = true

    resources {
      memory = 2
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 30
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
      # --- НЕ УКАЗЫВАЕМ subnet_id ---
    }
  }
}
