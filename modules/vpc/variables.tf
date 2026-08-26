variable "project_name" {
  description = "Short name used to prefix all resource names and tags"
  type        = string
}

variable "environment" {
  description = "Environment tag, e.g. dev, staging, prod"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region - AZ suffixes (a/b) are appended to this"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 2 public subnets, one per AZ"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the 2 private subnets, one per AZ"
  type        = list(string)
  default     = ["10.1.11.0/24", "10.1.12.0/24"]
}
