output "yk_cluster_id" {
  value = yandex_kubernetes_cluster.ms-up-running.id
}

output "yk_cluster_name" {
  value = yandex_kubernetes_cluster.ms-up-running.name
}

output "yk_cluster_certificate_data" {
  value = yandex_kubernetes_cluster.ms-up-running.master[0].cluster_ca_certificate
}

output "yk_cluster_endpoint" {
  value = yandex_kubernetes_cluster.ms-up-running.master[0].external_v4_endpoint
}

output "yk_cluster_nodegroup_id" {
  value = yandex_kubernetes_node_group.ms-node-group.id
}
