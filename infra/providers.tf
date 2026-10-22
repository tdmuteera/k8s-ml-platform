provider "kind" {}

provider "kubernetes" {
  host                   = kind_cluster.ml.endpoint
  client_certificate     = kind_cluster.ml.client_certificate
  client_key             = kind_cluster.ml.client_key
  cluster_ca_certificate = kind_cluster.ml.cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = kind_cluster.ml.endpoint
    client_certificate     = kind_cluster.ml.client_certificate
    client_key             = kind_cluster.ml.client_key
    cluster_ca_certificate = kind_cluster.ml.cluster_ca_certificate
  }
}
