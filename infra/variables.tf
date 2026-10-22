variable "cluster_name" {
  description = "Name of the local kind cluster."
  type        = string
  default     = "k8s-ml-platform"
}

variable "host_http_port" {
  description = "Host port published for ingress HTTP. Traffic stays on 127.0.0.1."
  type        = number
  default     = 18080
}

variable "host_https_port" {
  description = "Host port published for ingress HTTPS. Traffic stays on 127.0.0.1."
  type        = number
  default     = 18443
}

variable "grafana_host_port" {
  description = "Host port published for the Grafana NodePort. Traffic stays on 127.0.0.1."
  type        = number
  default     = 13000
}

variable "grafana_node_port" {
  description = "NodePort used by the Grafana Service. This port is mapped to grafana_host_port."
  type        = number
  default     = 30180
}

variable "node_image" {
  description = "kind node image. Pinned to the default image of the kind release used by the provider."
  type        = string
  default     = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"
}

variable "enable_observability" {
  description = "Install kube-prometheus-stack and scrape the inference service."
  type        = bool
  default     = true
}

variable "tools_dir" {
  description = "Directory containing kind and kubectl. The Makefile sets TF_VAR_tools_dir."
  type        = string
  default     = ""
}
