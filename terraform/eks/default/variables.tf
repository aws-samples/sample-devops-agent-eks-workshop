variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "retail-store"
}

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# Alias for backward compatibility
variable "environment_name" {
  description = "Name of the environment (deprecated, use cluster_name instead)"
  type        = string
  default     = ""
}

variable "istio_enabled" {
  description = "Boolean value that enables istio."
  type        = bool
  default     = false
}

variable "opentelemetry_enabled" {
  description = "Boolean value that enables OpenTelemetry (ADOT)."
  type        = bool
  default     = false
}

variable "application_signals_enabled" {
  description = "Boolean value that enables CloudWatch Application Signals auto-instrumentation."
  type        = bool
  default     = true
}

variable "container_image_overrides" {
  type = object({
    default_repository = optional(string)
    default_tag        = optional(string)

    ui       = optional(string)
    catalog  = optional(string)
    cart     = optional(string)
    checkout = optional(string)
    orders   = optional(string)
  })
  default     = {}
  description = "Object that encapsulates any overrides to default values"
}

variable "enable_grafana" {
  description = "Boolean value that enables Amazon Managed Grafana. Requires AWS SSO to be configured in the account."
  type        = bool
  default     = false
}
