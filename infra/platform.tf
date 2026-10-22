resource "random_password" "api_key" {
  length  = 24
  special = false
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

resource "kubernetes_namespace_v1" "inference" {
  metadata {
    name = local.inference_namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "app.kubernetes.io/part-of"          = "k8s-ml-platform"
    }
  }

  depends_on = [kind_cluster.ml]
}

resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = local.ingress_namespace
    labels = {
      "app.kubernetes.io/part-of" = "k8s-ml-platform"
    }
  }

  depends_on = [kind_cluster.ml]
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = local.monitoring_namespace
    labels = {
      "app.kubernetes.io/part-of" = "k8s-ml-platform"
    }
  }

  depends_on = [kind_cluster.ml]
}

resource "null_resource" "local_path" {
  triggers = {
    cluster  = kind_cluster.ml.endpoint
    manifest = filesha256("${path.module}/manifests/local-path-storage.yaml")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = abspath("${path.module}/../scripts/install-local-path.sh")

    environment = {
      KUBECONFIG = local.kubeconfig_path
      MANIFEST   = abspath("${path.module}/manifests/local-path-storage.yaml")
      PATH       = "${local.tools_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  }

  depends_on = [kind_cluster.ml, null_resource.preload_images]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace_v1.ingress.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = local.ingress_chart_version

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  timeout          = 600

  values = [file("${path.module}/values/ingress-nginx.yaml")]

  depends_on = [null_resource.preload_images, null_resource.nftables_proxy]
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = local.metrics_chart_version

  wait    = true
  timeout = 600

  values = [file("${path.module}/values/metrics-server.yaml")]

  depends_on = [null_resource.preload_images, null_resource.nftables_proxy]
}

resource "helm_release" "monitoring" {
  count = var.enable_observability ? 1 : 0

  name       = "monitoring"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = local.monitoring_chart

  create_namespace = false
  wait             = true
  wait_for_jobs    = true
  timeout          = 900

  values = [
    templatefile("${path.module}/values/kube-prometheus-stack.yaml.tftpl", {
      grafana_host_port = var.grafana_host_port
      grafana_node_port = var.grafana_node_port
    })
  ]

  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = random_password.grafana.result
    }
  ]

  depends_on = [helm_release.ingress_nginx]
}

resource "helm_release" "inference" {
  name      = "inference"
  namespace = kubernetes_namespace_v1.inference.metadata[0].name
  chart     = abspath("${path.module}/../charts/inference")

  create_namespace = false
  wait             = true
  timeout          = 600

  set = [
    {
      name  = "serviceMonitor.enabled"
      value = var.enable_observability ? "true" : "false"
    },
    {
      name  = "podAnnotations.deployedHash"
      value = local.app_hash
      type  = "string"
    }
  ]

  set_sensitive = [
    {
      name  = "apiKey"
      value = random_password.api_key.result
    }
  ]

  depends_on = [
    null_resource.load_image,
    null_resource.local_path,
    helm_release.ingress_nginx,
    helm_release.metrics_server,
    helm_release.monitoring,
  ]
}
