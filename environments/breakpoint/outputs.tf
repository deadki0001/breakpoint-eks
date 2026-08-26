output "cluster_name" {
  value = aws_eks_cluster.breakpoint.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.breakpoint.endpoint
}

output "vpc_id" {
  value = aws_vpc.breakpoint.id
}

output "region" {
  value = var.aws_region
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.breakpoint.name} --region ${var.aws_region}"
}
