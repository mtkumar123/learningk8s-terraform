# =============================================================================
# Managed node group (the worker nodes).
#
# Built in sub-steps:
#   4a) Node IAM role      <-- this file, so far
#   4b) aws_eks_node_group (added next)
# =============================================================================

# ---- 4a) Node IAM role ------------------------------------------------------
# Each worker EC2 instance assumes this role. Note the trust principal is
# ec2.amazonaws.com (the INSTANCES assume it) -- unlike the cluster role, which
# is assumed by the EKS service. The node's kubelet uses this role's identity
# to authenticate to the cluster (EKS auto-recognizes node roles).
data "aws_iam_policy_document" "eks_nodes_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_nodes" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume.json

  tags = {
    Name = "${var.cluster_name}-node-role"
  }
}

# The three AWS-managed policies every EKS worker node needs:

# 1) Lets the kubelet register with the cluster and pull node config from EKS.
resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# 2) Lets the VPC CNI plugin manage ENIs / assign pod IPs from the VPC.
#    Required because we use the default AWS VPC CNI.
resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# 3) Lets nodes pull container images from Amazon ECR (read-only).
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# ---- 4b) Managed node group ------------------------------------------------
# AWS creates and operates the underlying Launch Template + Auto Scaling Group
# for us, joins nodes to the cluster automatically (EKS-optimized AMI + node
# role), and does drain-aware rolling updates on version/AMI changes.
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Workers launch in the private subnets (no public IPs; egress via NAT).
  subnet_ids = aws_subnet.private[*].id

  # Match the cluster version so kubelet <-> API stay in step. AWS picks the
  # matching EKS-optimized AMI for this version + ami_type.
  version = var.kubernetes_version

  # Graviton/arm64 EKS-optimized AL2023 image for t4g instances.
  ami_type       = var.node_ami_type
  instance_types = [var.node_instance_type]
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  # Capacity bounds. desired_size is the starting count; min/max are the range
  # a scaler (Cluster Autoscaler / Karpenter, not installed yet) could move
  # within. On its own the group just holds desired_size nodes.
  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # During rolling updates, allow at most 1 node unavailable at a time.
  update_config {
    max_unavailable = 1
  }

  # The node role's policies must exist before nodes try to join, and the
  # cluster must be up. Terraform infers the cluster dependency from the
  # reference above; the policy attachments are made explicit here.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  # desired_size can drift if a scaler adjusts it later; ignoring it prevents
  # Terraform from resetting the count on every apply. (Safe to remove if you
  # never add autoscaling.)
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = {
    Name = "${var.cluster_name}-ng"
  }
}
