variable "aws_account_id" {
  description = "Your AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into - us-west-1 to keep SENTRY isolated from THRESHOLD in us-west-2"
  type        = string
  default     = "us-west-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "sentry-eks-dev"
}

variable "sso_admin_role_arn" {
  description = "Your SSO admin role ARN, used for cluster access entry"
  type        = string
}

variable "grafana_service_account_token" {
  description = "Grafana Cloud service account token - passed in via GitHub Actions secret, never committed"
  type        = string
  sensitive   = true
}
