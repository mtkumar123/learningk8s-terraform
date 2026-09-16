# Outputs surface useful values after `terraform apply`. Later steps (and you)
# reference these instead of hunting for IDs in the AWS console.

output "cluster_security_group_id" {
  description = "Security group ID to attach to all cluster nodes"
  value       = aws_security_group.cluster.id
}

output "vpc_id" {
  description = "ID of the cluster VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets where cluster nodes will run"
  value       = aws_subnet.private[*].id
}

# ---- Compute outputs --------------------------------------------------------

output "control_plane_instance_ids" {
  description = "Instance IDs of the control plane nodes (SSM in with: aws ssm start-session --target <id>)"
  value       = aws_instance.control_plane[*].id
}

output "control_plane_private_ips" {
  description = "Private IPs of the control plane nodes"
  value       = aws_instance.control_plane[*].private_ip
}

output "control_plane_endpoint" {
  description = "The NLB DNS name used as the kubeadm --control-plane-endpoint"
  value       = aws_lb.control_plane.dns_name
}

output "worker_asg_name" {
  description = "Name of the worker Auto Scaling Group (scale by changing its desired capacity)"
  value       = aws_autoscaling_group.worker.name
}
