# infra/terraform/variables.tf
variable "yc_token" {
  description = "OAuth token for Yandex Cloud"
  type        = string
}

variable "yc_cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "yc_folder_id" {
  description = "Yandex Folder ID"
  type        = string
}
