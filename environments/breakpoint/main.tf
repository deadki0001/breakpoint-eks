# ##############################################################################
# BREAKPOINT-EKS (project codename THRESHOLD)
#
# Standalone cluster for labbing purposes.
# Deployed to us-west-2 on purpose - avoids touching existing workloads in
# us-east-1/us-east-2 and keeps blast radius and cost tracking isolated.
#
# Purpose: deliberately push this cluster past its resource limits under a
# generated load, and observe/demonstrate Prometheus scraping the resulting
# metrics, Grafana visualizing them, and the Horizontal Pod Autoscaler (HPA)
# reacting in real time - plus an AWS Load Balancer Controller distributing
# traffic across the scaled-out pods. The node sizing below is intentionally
# small (t3.small, not t3.medium) so the breaking point is easy and cheap to
# reach on demand.
#
# This file is intentionally thin - it wires together 3 reusable modules
# (vpc, eks-cluster, node-group) rather than declaring resources directly.
# Each module is self-contained and could be called again by a different
# environment (e.g. environments/breakpoint-staging) without duplicating code.
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
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
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
# 10.1.0.0/16 - deliberately a different range from lsd-payments (10.0.0.0/16)
# so the two VPCs can be peered later without a CIDR clash if that's ever
# needed. 2 AZs, 2 public + 2 private subnets, 1 NAT gateway.
# ##############################################################################

module "vpc" {
  source = "../../modules/vpc"

  project_name = "breakpoint-eks"
  environment  = "dev"
  aws_region   = var.aws_region
}


# ##############################################################################
# EKS CLUSTER (control plane)
# ##############################################################################

module "eks_cluster" {
  source = "../../modules/eks"

  project_name        = "breakpoint-eks-dev"
  environment          = "dev"
  cluster_name         = var.cluster_name
  private_subnet_ids   = module.vpc.private_subnet_ids
  sso_admin_role_arn   = var.sso_admin_role_arn
}


# ##############################################################################
# NODE GROUP (workers + addons)
# 2x t3.small (2 vCPU / 2GB each), desired = 2. Deliberately smaller than a
# typical dev cluster - the whole point of this project is to reach real
# resource pressure quickly and cheaply so HPA has something genuine to
# react to. min = 1 so the group never scales to zero by accident and you
# always have to explicitly destroy it to stop paying for it.
# ##############################################################################

module "node_group" {
  source = "../../modules/cluster-addons"

  project_name       = "breakpoint-eks-dev"
  environment        = "dev"
  cluster_name       = module.eks_cluster.cluster_name
  private_subnet_ids = module.vpc.private_subnet_ids
  oidc_provider_arn  = module.eks_cluster.oidc_provider_arn
  oidc_provider_url  = module.eks_cluster.oidc_provider_url

  instance_types = ["t3.small"]
  desired_size   = 2
  min_size       = 1
  max_size       = 3
}


# ##############################################################################
# GRAFANA CLOUD ONCALL
# Manages the Alertmanager integration and escalation chain in Grafana Cloud
# via Terraform rather than clicking through the UI. This is separate from
# the in-cluster kube-prometheus-stack - it talks to Grafana Cloud's API,
# not the EKS cluster. Alertmanager (running in-cluster) gets pointed at
# the webhook URL this module outputs, wired in via a Helm value or
# Alertmanager config, not via this module directly.
# ##############################################################################

module "oncall" {
  source = "../../modules/grafana-oncall"

  project_name                = "breakpoint-eks"
  grafana_oncall_access_token = var.grafana_oncall_access_token
  grafana_oncall_url          = "https://oncall-prod-eu-west-6.grafana.net/oncall/api/v1"
  grafana_oncall_username     = "adkinsdevon"
}
