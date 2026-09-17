# Input variables for the EKS project. Defaults are set for a small, single
# managed-node-group learning cluster in eu-west-1. Override in terraform.tfvars.

# ---- Account / region -------------------------------------------------------

variable "region" {
  description = "AWS region where the cluster is provisioned"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI/SSO profile Terraform uses to authenticate. Set this in terraform.tfvars (not committed); see example.tfvars."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster; used for naming and tagging."
  type        = string
  default     = "learn-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version (control plane + node group)."
  type        = string
  default     = "1.36"
}

variable "admin_role_arn" {
  description = "IAM role ARN granted cluster-admin via an EKS access entry (your SSO role). Set in terraform.tfvars (not committed); see example.tfvars. Use the underlying role ARN under /aws-reserved/sso.amazonaws.com/, NOT the assumed-role session ARN."
  type        = string
}

# ---- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread the cluster across (EKS requires >= 2; we use 3)."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "public_subnet_cidr" {
  description = "CIDR for the primary public subnet (holds the NAT Gateway). Lives in availability_zones[0]."
  type        = string
  default     = "10.0.0.0/24"
}

variable "public_subnet_cidr_b" {
  description = "CIDR for the second public subnet. An internet-facing ALB requires public subnets in >= 2 AZs. Lives in availability_zones[1]."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets (hold the worker nodes). One per AZ."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# ---- Managed node group -----------------------------------------------------

variable "node_instance_type" {
  description = "Instance type for worker nodes (Graviton/arm64)."
  type        = string
  default     = "t4g.medium"
}

variable "node_ami_type" {
  description = "EKS-optimized AMI family for the node group. AL2023_ARM_64_STANDARD matches t4g/arm64."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT capacity for the node group."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes to start with."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes (upper bound for scaling)."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Root EBS volume size (GB) per worker node."
  type        = number
  default     = 20
}
