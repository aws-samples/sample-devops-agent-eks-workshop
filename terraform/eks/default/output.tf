output "configure_kubectl" {
  description = "Command to update kubeconfig for this cluster"
  value       = module.retail_app_eks.configure_kubectl
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = local.cluster_name
}

output "region" {
  description = "AWS region where the cluster is deployed"
  value       = var.region
}

output "retail_app_url" {
  description = "URL to access the retail store application"
  value = try(
    "http://${data.kubernetes_service.ui_service.status[0].load_balancer[0].ingress[0].hostname}",
    "LoadBalancer provisioning - run: kubectl get svc -n ui ui"
  )
}
