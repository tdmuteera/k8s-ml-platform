locals {
  tools_dir             = var.tools_dir != "" ? var.tools_dir : abspath("${path.module}/../.tools")
  kubeconfig_path       = abspath("${path.module}/.kube/config")
  image_ref             = "k8s-ml-inference:local"
  inference_namespace   = "ml-inference"
  monitoring_namespace  = "monitoring"
  ingress_namespace     = "ingress-nginx"
  ingress_chart_version = "4.15.1"
  metrics_chart_version = "3.14.0"
  monitoring_chart      = "92.11.0"

  app_root_files = [
    "${path.module}/../app/Dockerfile",
    "${path.module}/../app/requirements.txt",
  ]
  app_python_files = [
    for relative in sort(fileset("${path.module}/../app/src", "**/*.py")) :
    "${path.module}/../app/src/${relative}"
  ]
  app_hash = sha1(join("", [
    for path in concat(local.app_root_files, local.app_python_files) : filesha1(path)
  ]))
}
