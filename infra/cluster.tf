resource "null_resource" "kubeconfig_dir" {
  triggers = {
    path = local.kubeconfig_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "mkdir -p ${dirname(local.kubeconfig_path)}"
  }
}

resource "kind_cluster" "ml" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = local.kubeconfig_path

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 80
        host_port      = var.host_http_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = var.host_https_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }

      extra_port_mappings {
        container_port = var.grafana_node_port
        host_port      = var.grafana_host_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
    }
  }

  depends_on = [null_resource.kubeconfig_dir]
}

resource "null_resource" "nftables_proxy" {
  triggers = {
    cluster = kind_cluster.ml.endpoint
    script  = filesha256("${path.module}/../scripts/enable-nftables-proxy.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = abspath("${path.module}/../scripts/enable-nftables-proxy.sh")

    environment = {
      KUBECONFIG = local.kubeconfig_path
      PATH       = "${local.tools_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  }

  depends_on = [kind_cluster.ml]
}
