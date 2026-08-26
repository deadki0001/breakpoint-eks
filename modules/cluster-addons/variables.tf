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
  description = "Name of the EKS cluster from the eks-cluster module"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from the VPC module - nodes launch here"
  type        = list(string)
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN from the eks-cluster module, used for the EBS CSI IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL from the eks-cluster module, used for the EBS CSI IRSA trust policy"
  type        = string
}

variable "instance_types" {
  description = "EC2 instance types for the node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}
