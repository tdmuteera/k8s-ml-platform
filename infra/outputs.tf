output "inference_url" {
  description = "Base URL for the inference service on this machine."
  value       = "http://127.0.0.1:${var.host_http_port}"
}

output "grafana_url" {
  description = "Base URL for Grafana on this machine. Empty when observability is disabled."
  value       = var.enable_observability ? "http://127.0.0.1:${var.grafana_host_port}" : ""
}

output "grafana_user" {
  description = "Grafana admin user name."
  value       = "admin"
}

output "api_key" {
  description = "API key required by the predict endpoint."
  value       = random_password.api_key.result
  sensitive   = true
}

output "grafana_password" {
  description = "Grafana admin password."
  value       = random_password.grafana.result
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Kubeconfig for the local kind cluster."
  value       = local.kubeconfig_path
}

output "observability_enabled" {
  description = "Whether Prometheus and Grafana are installed."
  value       = var.enable_observability
}

output "namespace" {
  description = "Namespace of the inference service."
  value       = local.inference_namespace
}

output "image_ref" {
  description = "Local image name loaded into the kind node."
  value       = local.image_ref
}

output "cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.ml.name
}
