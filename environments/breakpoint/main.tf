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
  host                   = aws_eks_cluster.breakpoint.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.breakpoint.certificate_authority[0].data)

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
#
# 10.1.0.0/16 - deliberately a different range from lsd-payments (10.0.0.0/16)
# so the two VPCs can be peered later without a CIDR clash if that's ever
# needed. 2 AZs, 2 public + 2 private subnets, 1 NAT gateway.
# ##############################################################################

resource "aws_vpc" "breakpoint" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "breakpoint-eks-vpc"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.breakpoint.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "breakpoint-eks-public-az1"
    "kubernetes.io/role/elb" = "1"
    Project                  = "breakpoint-eks"
    Environment              = "dev"
    ManagedBy                = "terraform"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.breakpoint.id
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name                     = "breakpoint-eks-public-az2"
    "kubernetes.io/role/elb" = "1"
    Project                  = "breakpoint-eks"
    Environment              = "dev"
    ManagedBy                = "terraform"
  }
}

resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.breakpoint.id
  cidr_block        = "10.1.11.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name                              = "breakpoint-eks-private-az1"
    "kubernetes.io/role/internal-elb" = "1"
    Project                           = "breakpoint-eks"
    Environment                       = "dev"
    ManagedBy                         = "terraform"
  }
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.breakpoint.id
  cidr_block        = "10.1.12.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name                              = "breakpoint-eks-private-az2"
    "kubernetes.io/role/internal-elb" = "1"
    Project                           = "breakpoint-eks"
    Environment                       = "dev"
    ManagedBy                         = "terraform"
  }
}

resource "aws_internet_gateway" "breakpoint" {
  vpc_id = aws_vpc.breakpoint.id

  tags = {
    Name        = "breakpoint-eks-igw"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.breakpoint]

  tags = {
    Name        = "breakpoint-eks-nat-eip"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_nat_gateway" "breakpoint" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_az1.id

  tags = {
    Name        = "breakpoint-eks-nat"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.breakpoint.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.breakpoint.id
  }

  tags = {
    Name        = "breakpoint-eks-public-rt"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.breakpoint.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.breakpoint.id
  }

  tags = {
    Name        = "breakpoint-eks-private-rt"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "private_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private.id
}


# ##############################################################################
# EKS CLUSTER IAM ROLE
# ##############################################################################

resource "aws_iam_role" "cluster" {
  name        = "breakpoint-eks-dev-cluster-role"
  description = "Role used by EKS control plane to call AWS APIs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "breakpoint-eks-dev-cluster-role"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ##############################################################################
# EKS CLUSTER
#
# Same version as lsd-payments (1.34) for consistency. Public endpoint access
# stays on so kubectl works from your laptop without a bastion - acceptable
# for a learning cluster you tear down daily.
# ##############################################################################

resource "aws_eks_cluster" "breakpoint" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.34"

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Name        = var.cluster_name
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}


# ##############################################################################
# OIDC PROVIDER
# Needed so the EBS CSI driver can assume an IAM role via IRSA - Elasticsearch
# needs persistent volumes for its data nodes, and that's what provisions them.
# ##############################################################################

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.breakpoint.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.breakpoint.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "breakpoint-eks-dev-oidc"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}


# ##############################################################################
# NODE IAM ROLE
# ##############################################################################

resource "aws_iam_role" "node" {
  name        = "breakpoint-eks-dev-node-role"
  description = "Role used by EKS worker nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "breakpoint-eks-dev-node-role"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "node_eks_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ##############################################################################
# EBS CSI IRSA ROLE
# Trust policy scoped to the ebs-csi-controller-sa service account only.
# ##############################################################################

data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "breakpoint-eks-dev-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json

  tags = {
    Name        = "breakpoint-eks-dev-ebs-csi-role"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


# ##############################################################################
# LAUNCH TEMPLATE - IMDSv2 enforced
# ##############################################################################

resource "aws_launch_template" "node" {
  name        = "breakpoint-eks-dev-node-lt"
  description = "Launch template for BREAKPOINT learning nodes - enforces IMDSv2"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "breakpoint-eks-dev-node"
      Project     = "breakpoint-eks"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}


# ##############################################################################
# MANAGED NODE GROUP
#
# 2x t3.small (2 vCPU / 2GB each), desired = 2. Deliberately smaller than a
# typical dev cluster - the whole point of this project is to reach real
# resource pressure quickly and cheaply so HPA has something genuine to
# react to. min = 1 so the group never scales to zero by accident and you
# always have to explicitly destroy it to stop paying for it.
# ##############################################################################

resource "aws_eks_node_group" "breakpoint" {
  cluster_name    = aws_eks_cluster.breakpoint.name
  node_group_name = "breakpoint-eks-dev-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.small"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  tags = {
    Name        = "breakpoint-eks-dev-nodes"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_eks_worker,
    aws_iam_role_policy_attachment.node_ecr_read,
    aws_iam_role_policy_attachment.node_cni
  ]
}


# ##############################################################################
# EKS ADD-ONS
# ##############################################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.breakpoint.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.breakpoint.name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_eks_node_group.breakpoint]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.breakpoint.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.breakpoint.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_eks_node_group.breakpoint]
}


# ##############################################################################
# CLUSTER ACCESS ENTRY - your SSO admin role
# ##############################################################################

resource "aws_eks_access_entry" "sso_admin" {
  cluster_name  = aws_eks_cluster.breakpoint.name
  principal_arn = var.sso_admin_role_arn
  type          = "STANDARD"

  tags = {
    Name        = "breakpoint-eks-dev-sso-admin"
    Project     = "breakpoint-eks"
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [aws_eks_cluster.breakpoint]
}

resource "aws_eks_access_policy_association" "sso_admin" {
  cluster_name  = aws_eks_cluster.breakpoint.name
  principal_arn = var.sso_admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.sso_admin]
}
