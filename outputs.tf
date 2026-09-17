# Handy values surfaced after apply.

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = aws_eks_cluster.main.version
}

output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.main.node_group_name
}

# Copy-paste command to point your local kubectl at this cluster. After apply,
# run this once, then `kubectl get nodes` should list your worker(s).
output "update_kubeconfig_command" {
  description = "Run this to configure kubectl for the cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.region} --profile ${var.aws_profile}"
}
