# ##############################################################################
# SENTRY-EKS (project codename SENTRY)
#
# Standalone cluster for demonstrating DevSecOps admission control -
# specifically a validating webhook that blocks container images tagged
# :latest from being deployed to the cluster, enforcing immutable image
# tagging policy at the infrastructure level.
#
# Deployed to us-west-1 (separate from THRESHOLD in us-west-2) so both
# clusters can run simultaneously and be switched between via kubectl
# context during a demo. Note: us-west-1 only has AZs a and c (no b),
# so the VPC module's AZ suffixes are explicitly overridden here.
#
# t3.small nodes are sufficient - this cluster only needs to run the
# admission controller and a handful of test deployments, no load testing.
# ##############################################################################

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name", var.cluster_name,
      "--region", var.aws_region
    ]
  }
}


# ##############################################################################
# VPC
# 10.2.0.0/16 - different range from THRESHOLD (10.1.0.0/16) and
# lsd-payments (10.0.0.0/16) to avoid CIDR conflicts if VPCs are ever
# peered. us-west-1 only has AZs a and c, so az_suffixes is overridden
# explicitly here rather than relying on the module's default of a and b.
# ##############################################################################

module "vpc" {
  source = "../../modules/vpc"

  project_name         = "sentry-eks"
  environment          = "dev"
  aws_region           = var.aws_region
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]
}


# ##############################################################################
# EKS CLUSTER (control plane)
# ##############################################################################

module "eks_cluster" {
  source = "../../modules/eks"

  project_name       = "sentry-eks-dev"
  environment        = "dev"
  cluster_name       = var.cluster_name
  private_subnet_ids = module.vpc.private_subnet_ids
  sso_admin_role_arn = var.sso_admin_role_arn
}


# ##############################################################################
# NODE GROUP (workers + addons)
# t3.small, 2 nodes - enough to run the admission controller and test
# deployments without the resource overhead THRESHOLD needed for load testing.
# ##############################################################################

module "node_group" {
  source = "../../modules/cluster-addons"

  project_name       = "sentry-eks-dev"
  environment        = "dev"
  cluster_name       = module.eks_cluster.cluster_name
  private_subnet_ids = module.vpc.private_subnet_ids
  oidc_provider_arn  = module.eks_cluster.oidc_provider_arn
  oidc_provider_url  = module.eks_cluster.oidc_provider_url

  instance_types = ["t3.small"]
  desired_size   = 2
  min_size       = 1
  max_size       = 2
}
