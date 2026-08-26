# ##############################################################################
# EKS CLUSTER MODULE
#
# The control plane only - cluster IAM role, the cluster itself, OIDC
# provider (needed for IRSA, e.g. the EBS CSI driver or ALB controller
# assuming IAM roles via Kubernetes service accounts), and SSO access
# entries. Worker nodes live in a separate node-group module since they
# have a different lifecycle and scale independently of the control plane.
# ##############################################################################

resource "aws_iam_role" "cluster" {
  name        = "${var.project_name}-cluster-role"
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
    Name        = "${var.project_name}-cluster-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Name        = var.cluster_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]

  tags = {
    Name        = "${var.project_name}-oidc"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_eks_access_entry" "sso_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.sso_admin_role_arn
  type          = "STANDARD"

  tags = {
    Name        = "${var.project_name}-sso-admin"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_access_policy_association" "sso_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.sso_admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.sso_admin]
}
