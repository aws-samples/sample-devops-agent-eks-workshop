locals {
  istio_labels = {
    istio-injection = "enabled"
  }

  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "terraform"
    clusters = [{
      name = module.retail_app_eks.eks_cluster_id
      cluster = {
        certificate-authority-data = module.retail_app_eks.cluster_certificate_authority_data
        server                     = module.retail_app_eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = "terraform"
      context = {
        cluster = module.retail_app_eks.eks_cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        token = data.aws_eks_cluster_auth.this.token
      }
    }]
  })
}

module "container_images" {
  source = "../../lib/images"

  container_image_overrides = var.container_image_overrides
}

resource "null_resource" "cluster_blocker" {
  triggers = {
    "blocker" = module.retail_app_eks.cluster_blocker_id
  }
}

resource "null_resource" "addons_blocker" {
  triggers = {
    "blocker" = module.retail_app_eks.addons_blocker_id
  }
}

resource "time_sleep" "workloads" {
  create_duration  = "30s"
  destroy_duration = "60s"

  depends_on = [
    null_resource.addons_blocker
  ]
}

# For EKS Auto Mode, nodes are provisioned on-demand and don't have trunk ENI labels
# Simply wait for the addons to be ready before deploying workloads
resource "kubernetes_namespace_v1" "catalog" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "catalog"

    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "helm_release" "catalog" {
  name       = "catalog"
  repository = "oci://public.ecr.aws/aws-containers"
  chart      = "retail-store-sample-catalog-chart"
  version    = "1.3.0"

  namespace = kubernetes_namespace_v1.catalog.metadata[0].name

  values = [
    templatefile("${path.module}/values/catalog.yaml", {
      image_repository              = module.container_images.result.catalog.repository
      image_tag                     = module.container_images.result.catalog.tag
      opentelemetry_enabled         = var.opentelemetry_enabled
      opentelemetry_instrumentation = local.opentelemetry_instrumentation
      database_endpoint             = "${module.dependencies.catalog_db_endpoint}:${module.dependencies.catalog_db_port}"
      database_username             = module.dependencies.catalog_db_master_username
      database_password             = module.dependencies.catalog_db_master_password
      security_group_id             = aws_security_group.catalog.id
      # Note: Catalog is Go - Application Signals doesn't support Go auto-instrumentation
    })
  ]
}

resource "kubernetes_namespace_v1" "carts" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "carts"

    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "helm_release" "carts" {
  name       = "carts"
  repository = "oci://public.ecr.aws/aws-containers"
  chart      = "retail-store-sample-cart-chart"
  version    = "1.3.0"

  namespace = kubernetes_namespace_v1.carts.metadata[0].name

  values = [
    templatefile("${path.module}/values/carts.yaml", {
      image_repository               = module.container_images.result.cart.repository
      image_tag                      = module.container_images.result.cart.tag
      opentelemetry_enabled          = var.opentelemetry_enabled
      opentelemetry_instrumentation  = local.opentelemetry_instrumentation
      application_signals_enabled    = var.application_signals_enabled
      role_arn                       = module.iam_assumable_role_carts.iam_role_arn
      table_name                     = module.dependencies.carts_dynamodb_table_name
    })
  ]
}

resource "kubernetes_namespace_v1" "checkout" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "checkout"

    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "helm_release" "checkout" {
  name       = "checkout"
  repository = "oci://public.ecr.aws/aws-containers"
  chart      = "retail-store-sample-checkout-chart"
  version    = "1.3.0"

  namespace = kubernetes_namespace_v1.checkout.metadata[0].name

  values = [
    templatefile("${path.module}/values/checkout.yaml", {
      image_repository               = module.container_images.result.checkout.repository
      image_tag                      = module.container_images.result.checkout.tag
      opentelemetry_enabled          = var.opentelemetry_enabled
      opentelemetry_instrumentation  = local.opentelemetry_instrumentation
      application_signals_enabled    = var.application_signals_enabled
      redis_address                  = module.dependencies.checkout_elasticache_primary_endpoint
      redis_port                     = module.dependencies.checkout_elasticache_port
      security_group_id              = aws_security_group.checkout.id
    })
  ]
}

resource "kubernetes_namespace_v1" "orders" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "orders"

    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "helm_release" "orders" {
  name       = "orders"
  repository = "oci://public.ecr.aws/aws-containers"
  chart      = "retail-store-sample-orders-chart"
  version    = "1.3.0"

  namespace = kubernetes_namespace_v1.orders.metadata[0].name

  values = [
    templatefile("${path.module}/values/orders.yaml", {
      image_repository               = module.container_images.result.orders.repository
      image_tag                      = module.container_images.result.orders.tag
      opentelemetry_enabled          = var.opentelemetry_enabled
      opentelemetry_instrumentation  = local.opentelemetry_instrumentation
      application_signals_enabled    = var.application_signals_enabled
      database_endpoint_host         = module.dependencies.orders_db_endpoint
      database_endpoint_port         = module.dependencies.orders_db_port
      database_name                  = module.dependencies.orders_db_database_name
      database_username              = module.dependencies.orders_db_master_username
      database_password              = module.dependencies.orders_db_master_password
      rabbitmq_endpoint              = module.dependencies.mq_broker_endpoint
      rabbitmq_username              = module.dependencies.mq_user
      rabbitmq_password              = module.dependencies.mq_password
      security_group_id              = aws_security_group.orders.id
    })
  ]
}

# EKS Auto Mode: IngressClass and IngressClassParams for ALB
# Using null_resource with kubectl to avoid plan-time cluster connection issues
resource "null_resource" "ingress_class" {
  depends_on = [
    time_sleep.workloads
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(local.kubeconfig)
    }

    command = <<-EOT
      cat <<EOF | kubectl apply --kubeconfig <(echo $KUBECONFIG | base64 -d) -f -
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  name: alb
spec:
  scheme: internet-facing
---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: alb
EOF
    EOT
  }
}

resource "kubernetes_namespace_v1" "ui" {
  depends_on = [
    time_sleep.workloads
  ]

  metadata {
    name = "ui"

    labels = var.istio_enabled ? local.istio_labels : {}
  }
}

resource "helm_release" "ui" {
  depends_on = [
    null_resource.ingress_class,
    helm_release.catalog,
    helm_release.carts,
    helm_release.checkout,
    helm_release.orders
  ]

  name       = "ui"
  repository = "oci://public.ecr.aws/aws-containers"
  chart      = "retail-store-sample-ui-chart"
  version    = "1.3.0"

  namespace = kubernetes_namespace_v1.ui.metadata[0].name

  values = [
    templatefile("${path.module}/values/ui.yaml", {
      image_repository               = module.container_images.result.ui.repository
      image_tag                      = module.container_images.result.ui.tag
      opentelemetry_enabled          = var.opentelemetry_enabled
      opentelemetry_instrumentation  = local.opentelemetry_instrumentation
      application_signals_enabled    = var.application_signals_enabled
      istio_enabled                  = var.istio_enabled
      alb_logs_bucket                = aws_s3_bucket.alb_logs.id
      cluster_name                   = local.cluster_name
    })
  ]
}

resource "time_sleep" "restart_pods" {
  triggers = {
    opentelemetry_enabled = var.opentelemetry_enabled
  }

  create_duration = "30s"

  depends_on = [
    helm_release.ui
  ]
}

resource "null_resource" "restart_pods" {
  depends_on = [time_sleep.restart_pods]

  triggers = {
    opentelemetry_enabled = var.opentelemetry_enabled
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = base64encode(local.kubeconfig)
    }

    command = <<-EOT
      kubectl delete pod -A -l app.kubernetes.io/owner=retail-store-sample --kubeconfig <(echo $KUBECONFIG | base64 -d)
    EOT
  }
}
