# CloudWatch Observability IAM Role
# Note: This role is created before the cluster, using a placeholder OIDC provider pattern
# The actual OIDC provider ARN is populated after cluster creation
resource "aws_iam_role" "cloudwatch_observability" {
  name = "${var.environment_name}-cloudwatch-observability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks_cluster.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
            "${replace(module.eks_cluster.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
          }
        }
      }
    ]
  })

  tags = var.tags

  depends_on = [module.eks_cluster]
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  role       = aws_iam_role.cloudwatch_observability.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_xray" {
  role       = aws_iam_role.cloudwatch_observability.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

# EKS Managed Add-on: kube-state-metrics
resource "aws_eks_addon" "kube_state_metrics" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "kube-state-metrics"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [module.eks_cluster]
}

# EKS Managed Add-on: prometheus-node-exporter
resource "aws_eks_addon" "prometheus_node_exporter" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "prometheus-node-exporter"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [module.eks_cluster]
}

# EKS Managed Add-on: EFS CSI Driver
resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [module.eks_cluster]
}

# EKS Managed Add-on: Secrets Store CSI Driver Provider
resource "aws_eks_addon" "secrets_store_csi_driver" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "aws-secrets-store-csi-driver-provider"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [module.eks_cluster]
}

# EKS Managed Add-on: CloudWatch Observability
# Enables Container Insights with enhanced observability and Application Signals for APM
# Application Signals supports Java, Python, Node.js, and .NET auto-instrumentation
# Note: Catalog service is Go - Application Signals doesn't support Go auto-instrumentation
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = "v4.7.0-eksbuild.1"
  service_account_role_arn    = aws_iam_role.cloudwatch_observability.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Application Signals configuration
  # The add-on webhook will auto-inject instrumentation when pods have the annotation:
  #   instrumentation.opentelemetry.io/inject-java: "true"
  #   instrumentation.opentelemetry.io/inject-nodejs: "true"
  configuration_values = jsonencode({
    agent = {
      config = {
        logs = {
          metrics_collected = {
            application_signals = {}
            kubernetes = {
              enhanced_container_insights = true
            }
          }
        }
        traces = {
          traces_collected = {
            application_signals = {}
          }
        }
      }
    }
    containerLogs = {
      enabled = true
    }
  })

  tags = var.tags

  depends_on = [
    module.eks_cluster,
    aws_iam_role.cloudwatch_observability,
    aws_iam_role_policy_attachment.cloudwatch_observability,
    aws_iam_role_policy_attachment.cloudwatch_observability_xray
  ]
}

# IAM Role for Network Flow Monitoring Agent
resource "aws_iam_role" "network_flow_monitoring" {
  name = "${var.environment_name}-network-flow-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks_cluster.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks_cluster.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
            "${replace(module.eks_cluster.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:amazon-network-flow-monitor:aws-network-flow-monitor-agent-service-account"
          }
        }
      }
    ]
  })

  tags = var.tags

  depends_on = [module.eks_cluster]
}

resource "aws_iam_role_policy" "network_flow_monitoring" {
  name = "${var.environment_name}-network-flow-monitoring-policy"
  role = aws_iam_role.network_flow_monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "networkflowmonitor:Publish",
          "networkflowmonitor:StartQueryWorkloadInsightsTopContributors",
          "networkflowmonitor:GetQueryResultsWorkloadInsightsTopContributors",
          "networkflowmonitor:StopQueryWorkloadInsightsTopContributors",
          "networkflowmonitor:GetQueryStatusWorkloadInsightsTopContributors",
          "networkflowmonitor:StartQueryWorkloadInsightsTopContributorsData",
          "networkflowmonitor:GetQueryResultsWorkloadInsightsTopContributorsData",
          "networkflowmonitor:StopQueryWorkloadInsightsTopContributorsData",
          "networkflowmonitor:GetQueryStatusWorkloadInsightsTopContributorsData",
          "networkflowmonitor:CreateScope",
          "networkflowmonitor:DeleteScope",
          "networkflowmonitor:ListScopes",
          "networkflowmonitor:GetScope",
          "networkflowmonitor:UpdateScope"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/network-flow-monitor/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      }
    ]
  })
}

# EKS Managed Add-on: Network Flow Monitoring Agent (Container Network Observability)
resource "aws_eks_addon" "network_flow_monitoring" {
  cluster_name                = module.eks_cluster.cluster_name
  addon_name                  = "aws-network-flow-monitoring-agent"
  service_account_role_arn    = aws_iam_role.network_flow_monitoring.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags

  depends_on = [module.eks_cluster]
}

# Note: Network Flow Monitor Scope and Monitor resources are managed outside of Terraform
# until native AWS provider support is available. Configure via AWS Console or CLI:
# - aws networkflowmonitor create-scope
# - aws networkflowmonitor create-monitor

# Amazon Managed Service for Prometheus Workspace
resource "aws_prometheus_workspace" "retail_store" {
  alias = "${var.environment_name}-metrics"
  tags  = var.tags
}

# IAM Role for Prometheus Scraper
resource "aws_iam_role" "prometheus_scraper" {
  name = "${var.environment_name}-prometheus-scraper"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scraper.aps.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}


resource "aws_iam_role_policy" "prometheus_scraper" {
  name = "${var.environment_name}-prometheus-scraper-policy"
  role = aws_iam_role.prometheus_scraper.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite"
        ]
        Resource = aws_prometheus_workspace.retail_store.arn
      }
    ]
  })
}

# EKS Managed Prometheus Scraper
resource "aws_prometheus_scraper" "eks" {
  alias = "${var.environment_name}-scraper"

  source {
    eks {
      cluster_arn        = module.eks_cluster.cluster_arn
      subnet_ids         = var.subnet_ids
      security_group_ids = [module.eks_cluster.node_security_group_id]
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.retail_store.arn
    }
  }

  scrape_configuration = <<-EOT
global:
  scrape_interval: 30s
  external_labels:
    cluster: ${var.environment_name}

scrape_configs:
  # API Server metrics
  - job_name: kubernetes-apiservers
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https

  # Kubelet metrics (node level)
  - job_name: kubernetes-nodes
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/$1/proxy/metrics

  # cAdvisor metrics (container level)
  - job_name: kubernetes-nodes-cadvisor
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor

  # kube-state-metrics
  - job_name: kube-state-metrics
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - kube-state-metrics
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: kube-state-metrics
      - source_labels: [__meta_kubernetes_endpoint_port_name]
        action: keep
        regex: http
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_service_name]
        target_label: service

  # prometheus-node-exporter (node hardware/OS metrics)
  # Scrape via API server service proxy since AMP scraper runs outside the cluster
  - job_name: node-exporter
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
            - prometheus-node-exporter
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: prometheus-node-exporter
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node
      - source_labels: [__meta_kubernetes_endpoint_address_target_name]
        target_label: instance
      - target_label: __address__
        replacement: kubernetes.default.svc:443
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        regex: (.+);(.+);(.+)
        target_label: __metrics_path__
        replacement: /api/v1/namespaces/$1/services/$2:$3/proxy/metrics
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_service_name]
        target_label: service

  # Network Flow Monitor Agent (Container Network Observability)
  - job_name: network-flow-monitor
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - amazon-network-flow-monitor
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: keep
        regex: network-flow-monitor-agent
      - source_labels: [__meta_kubernetes_pod_ip]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: $1:51680
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node

  # Generic service endpoints with prometheus annotations
  - job_name: kubernetes-service-endpoints
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: service

  # Generic pods with prometheus annotations
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod

  # EKS Control Plane - kube-scheduler metrics
  - job_name: kube-scheduler
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    static_configs:
      - targets:
        - kubernetes.default.svc:443
    metrics_path: /apis/metrics.eks.amazonaws.com/v1/ksh/container/metrics

  # EKS Control Plane - kube-controller-manager metrics
  - job_name: kube-controller-manager
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    static_configs:
      - targets:
        - kubernetes.default.svc:443
    metrics_path: /apis/metrics.eks.amazonaws.com/v1/kcm/container/metrics
EOT

  tags = var.tags

  depends_on = [module.eks_cluster]
}

# Amazon Managed Grafana Workspace (Optional - requires AWS SSO)
resource "aws_grafana_workspace" "retail_store" {
  count = var.enable_grafana ? 1 : 0

  name                     = "${var.environment_name}-grafana"
  description              = "Grafana workspace for ${var.environment_name} EKS cluster monitoring"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  grafana_version          = "10.4"

  data_sources = [
    "PROMETHEUS",
    "CLOUDWATCH",
    "XRAY"
  ]

  tags = var.tags
}

# Note: Grafana admin user assignment is done manually after deployment
# To assign yourself as admin:
# 1. Go to Amazon Managed Grafana console
# 2. Select the workspace
# 3. Go to Authentication tab -> Assign new user or group
# 4. Select your SSO user and assign ADMIN role

# IAM Role for Grafana
resource "aws_iam_role" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.environment_name}-grafana"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# Policy for Grafana to read from AMP
resource "aws_iam_role_policy" "grafana_amp" {
  count = var.enable_grafana ? 1 : 0

  name = "${var.environment_name}-grafana-amp-policy"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy for Grafana to read CloudWatch
resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  count = var.enable_grafana ? 1 : 0

  role       = aws_iam_role.grafana[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# Policy for Grafana to read X-Ray
resource "aws_iam_role_policy_attachment" "grafana_xray" {
  count = var.enable_grafana ? 1 : 0

  role       = aws_iam_role.grafana[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess"
}

# Outputs for observability
output "prometheus_workspace_arn" {
  description = "ARN of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.retail_store.arn
}

output "prometheus_workspace_endpoint" {
  description = "Endpoint of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.retail_store.prometheus_endpoint
}

output "grafana_workspace_endpoint" {
  description = "Endpoint of the Amazon Managed Grafana workspace"
  value       = var.enable_grafana ? aws_grafana_workspace.retail_store[0].endpoint : null
}

output "grafana_workspace_id" {
  description = "ID of the Amazon Managed Grafana workspace"
  value       = var.enable_grafana ? aws_grafana_workspace.retail_store[0].id : null
}
