resource "null_resource" "load_image" {
  triggers = {
    app_hash = local.app_hash
    cluster  = kind_cluster.ml.endpoint
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = abspath("${path.module}/../scripts/load-image.sh")

    environment = {
      IMAGE        = local.image_ref
      CLUSTER_NAME = kind_cluster.ml.name
      KIND_BIN     = "${local.tools_dir}/kind"
      PATH         = "${local.tools_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  }

  depends_on = [kind_cluster.ml]
}

resource "null_resource" "preload_images" {
  triggers = {
    cluster = kind_cluster.ml.endpoint
    images  = filesha256("${path.module}/images.txt")
    script  = filesha256("${path.module}/../scripts/preload-images.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash"]
    command     = abspath("${path.module}/../scripts/preload-images.sh")

    environment = {
      CLUSTER_NAME = kind_cluster.ml.name
      CRANE_BIN    = "${local.tools_dir}/crane"
      IMAGES_FILE  = abspath("${path.module}/images.txt")
      PATH         = "${local.tools_dir}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    }
  }

  depends_on = [kind_cluster.ml]
}
