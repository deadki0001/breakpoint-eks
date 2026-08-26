variable "project_name" {
  description = "Short name used to prefix all resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment tag, e.g. dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version"
  type        = string
  default     = "1.34"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the VPC module - the control plane's ENIs live here"
  type        = list(string)
}

variable "sso_admin_role_arn" {
  description = "SSO admin role ARN to grant cluster-admin access via an access entry"
  type        = string
}
