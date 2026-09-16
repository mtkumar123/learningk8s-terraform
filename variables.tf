# Input variables for the project. Think of these like CloudFormation
# Parameters, but with defaults so you don't have to pass them every time.

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
  description = "Name of the Kubernetes cluster; used for tagging and (later) cloud integration discovery"
  type        = string
  default     = "learn-k8s"
}

# ---- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must NOT overlap the Pod CIDR (192.168.0.0/16) or Service CIDR (10.96.0.0/12) used later by kubeadm."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "The AZs to spread the cluster across (3 for HA control plane, one CP per AZ)"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "public_subnet_cidr" {
  description = "CIDR for the single public subnet (holds the NAT Gateway). Lives in availability_zones[0]."
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDRs for the private subnets (hold the k8s nodes). Index 0 -> AZ-a, 1 -> AZ-b, 2 -> AZ-c."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# ---- Compute (EC2 nodes) ----------------------------------------------------

variable "control_plane_instance_type" {
  description = "Instance type for the control plane node (Graviton/arm64). kubeadm needs >= 2 vCPU / 2 GB."
  type        = string
  default     = "t4g.medium"
}

variable "control_plane_count" {
  description = "Number of control-plane nodes (3 for HA; must be odd for etcd quorum)."
  type        = number
  default     = 3
}

variable "worker_instance_type" {
  description = "Instance type for worker nodes (Graviton/arm64)."
  type        = string
  default     = "t4g.medium"
}

variable "worker_count" {
  description = "Number of worker nodes to create."
  type        = number
  default     = 2
}

variable "node_root_volume_size" {
  description = "Root EBS volume size in GB for each node (room for container images + etcd)."
  type        = number
  default     = 20
}

variable "kubernetes_version" {
  description = "Kubernetes minor version to install (used to select the pkgs.k8s.io repo)."
  type        = string
  default     = "1.36"
}

variable "pod_cidr" {
  description = "Pod network CIDR. MUST NOT overlap the VPC CIDR. Used later by kubeadm/CNI."
  type        = string
  default     = "192.168.0.0/16"
}

variable "join_command_param_name" {
  description = "SSM Parameter Store name where the control plane publishes the kubeadm join command"
  type        = string
  default     = "/learn-k8s/join-command"
}

variable "cp_join_command_param_name" {
  description = "SSM parameter where the primary control plane publishes the control-plane join command (includes --certificate-key)"
  type        = string
  default     = "/learn-k8s/cp-join-command"
}

variable "calico_version" {
  description = "Calico release to install (matches the manifests URL tag)"
  type        = string
  default     = "v3.32.2"
}
