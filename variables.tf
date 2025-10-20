variable "yandex_zone" {
  type    = string
  default = "ru-central1-d"
}

variable "yandex_folder_id" {
  type = string
}

variable "env_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "ms_namespace" {
  type    = string
  default = "microservices"
}

variable "vpc_id" {
  type = string
}

variable "cluster_subnet_ids" {
  type = list(string)
}

variable "k8s_version" {
  type        = string
  default     = "1.28"
  description = "Kubernetes version"
}

variable "nodegroup_subnet_ids" {
  type = list(string)
}

variable "nodegroup_desired_size" {
  type    = number
  default = 1
}

variable "nodegroup_min_size" {
  type    = number
  default = 1
}

variable "nodegroup_max_size" {
  type    = number
  default = 5
}

variable "nodegroup_memory" {
  type        = number
  default     = 4
  description = "Memory in GB for worker nodes"
}

variable "nodegroup_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores for worker nodes"
}

variable "nodegroup_disk_size" {
  type = string
}

variable "nodegroup_instance_types" {
  type = list(string)
}