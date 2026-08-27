variable "aws_account_id" {
  description = "Your AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into - separate from us-east-1/us-east-2 where lsd-payments already runs"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "breakpoint-eks-dev"
}

variable "sso_admin_role_arn" {
  description = "Your SSO admin role ARN, used for cluster access entry"
  type        = string
}

variable "grafana_cloud_api_token" {
  description = "Grafana Cloud access policy token for managing OnCall resources - passed in via GitHub Actions secret, never committed"
  type        = string
  sensitive   = true
}
