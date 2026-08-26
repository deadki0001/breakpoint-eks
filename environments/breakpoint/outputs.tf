output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "region" {
  value = var.aws_region
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks_cluster.cluster_name} --region ${var.aws_region}"
}
