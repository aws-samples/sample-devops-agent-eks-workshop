data "aws_caller_identity" "current" {}

# IAM Role for EKS Auto Mode nodes
resource "aws_iam_role" "eks_auto_node" {
  name = "${var.environment_name}-eks-auto-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_auto_node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  role       = aws_iam_role.eks_auto_node.name
}

resource "aws_iam_role_policy_attachment" "eks_auto_node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.eks_auto_node.name
}

# IAM Role for EKS Auto Mode cluster (with additional Auto Mode policies)
resource "aws_iam_role" "eks_auto_cluster" {
  name = "${var.environment_name}-eks-auto-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Required policies for EKS Auto Mode cluster role
resource "aws_iam_role_policy_attachment" "eks_auto_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_auto_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_auto_compute_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.eks_auto_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_auto_block_storage_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.eks_auto_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_auto_load_balancing_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.eks_auto_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_auto_networking_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.eks_auto_cluster.name
}

module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  providers = {
    kubernetes = kubernetes.cluster
  }

  cluster_name                   = var.environment_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  # Use custom cluster role with Auto Mode policies
  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_auto_cluster.arn

  # Access configuration - API_AND_CONFIG_MAP mode
  authentication_mode = "API_AND_CONFIG_MAP"

  # Access entries for user and role
  # Note: cluster creator (kulkshya) automatically gets access via enable_cluster_creator_admin_permissions
  access_entries = {
    Administrator = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Administrator"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # EKS Auto Mode configuration
  cluster_compute_config = {
    enabled       = true
    node_pools    = ["general-purpose", "system"]
    node_role_arn = aws_iam_role.eks_auto_node.arn
  }

  # Disable self-managed addons for Auto Mode
  bootstrap_self_managed_addons = false

  # Auto Mode handles these - only keep metrics-server addon
  # CloudWatch observability addon is added separately to avoid circular dependency
  cluster_addons = {
    metrics-server = {
      most_recent = true
    }
  }

  vpc_id = var.vpc_id

  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.subnet_ids

  # Auto Mode manages compute - remove managed node groups
  eks_managed_node_groups = {}

  # Auto Mode manages node security groups - minimal additional rules needed
  node_security_group_additional_rules = {}

  # Enable EKS Auto Mode features
  enable_cluster_creator_admin_permissions = true

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_auto_cluster_policy,
    aws_iam_role_policy_attachment.eks_auto_compute_policy,
    aws_iam_role_policy_attachment.eks_auto_block_storage_policy,
    aws_iam_role_policy_attachment.eks_auto_load_balancing_policy,
    aws_iam_role_policy_attachment.eks_auto_networking_policy,
  ]
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks_cluster.cluster_name
  cluster_endpoint  = module.eks_cluster.cluster_endpoint
  cluster_version   = module.eks_cluster.cluster_version
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn

  # Auto Mode handles load balancing - disable ALB controller
  enable_aws_load_balancer_controller = false
  enable_cert_manager                 = true
}

resource "time_sleep" "addons" {
  create_duration  = "30s"
  destroy_duration = "30s"

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "null_resource" "cluster_blocker" {
  depends_on = [
    module.eks_cluster
  ]
}

resource "null_resource" "addons_blocker" {
  depends_on = [
    time_sleep.addons,
    aws_eks_addon.adot,
    aws_eks_addon.cloudwatch_observability
  ]
}

# Enable Network Policy Controller for EKS Auto Mode
# This ConfigMap enables the VPC CNI network policy controller on Auto Mode nodes
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/auto-net-pol.html
resource "kubernetes_config_map" "network_policy_controller" {
  provider = kubernetes.cluster

  metadata {
    name      = "amazon-vpc-cni"
    namespace = "kube-system"
  }

  data = {
    "enable-network-policy-controller" = "true"
  }

  depends_on = [
    module.eks_cluster
  ]
}
