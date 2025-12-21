locals {
  # Disabled Security Groups for Pods for EKS Auto Mode compatibility
  # Always use node security group for database access
  security_groups_active = false
  
  # Use cluster_name if set, otherwise fall back to environment_name for backward compatibility
  cluster_name = var.cluster_name != "" ? var.cluster_name : (var.environment_name != "" ? var.environment_name : "retail-store")
}

module "tags" {
  source = "../../lib/tags"

  environment_name = local.cluster_name
}

module "vpc" {
  source = "../../lib/vpc"

  environment_name = local.cluster_name

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

  tags = module.tags.result
}

module "dependencies" {
  source = "../../lib/dependencies"

  environment_name = local.cluster_name
  tags             = module.tags.result

  vpc_id     = module.vpc.inner.vpc_id
  subnet_ids = module.vpc.inner.private_subnets

  catalog_security_group_id  = local.security_groups_active ? aws_security_group.catalog.id : module.retail_app_eks.node_security_group_id
  orders_security_group_id   = local.security_groups_active ? aws_security_group.orders.id : module.retail_app_eks.node_security_group_id
  checkout_security_group_id = local.security_groups_active ? aws_security_group.checkout.id : module.retail_app_eks.node_security_group_id
}

module "retail_app_eks" {
  source = "../../lib/eks"

  providers = {
    kubernetes.cluster = kubernetes.cluster
    kubernetes.addons  = kubernetes

    helm = helm
  }

  environment_name      = local.cluster_name
  cluster_version       = "1.33"
  vpc_id                = module.vpc.inner.vpc_id
  vpc_cidr              = module.vpc.inner.vpc_cidr_block
  subnet_ids            = module.vpc.inner.private_subnets
  opentelemetry_enabled = var.opentelemetry_enabled
  enable_grafana        = var.enable_grafana
  tags                  = module.tags.result

  istio_enabled = var.istio_enabled
}
