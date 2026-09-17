# =============================================================================
# EKS cluster (the AWS-managed control plane).
#
# Built in sub-steps:
#   3a Cluster IAM role  <-- this file, so far
#   3b aws_eks_cluster   (added next)
# =============================================================================

# ---- 3a Cluster IAM role ---------------------------------------------------
# EKS assumes this role to manage AWS resources on your behalf (ENIs, security
# groups, load balancers). Two parts:
#   - assume_role_policy: the TRUST policy -- only the EKS service principal
#     (eks.amazonaws.com) may assume this role.
#   - the attached AmazonEKSClusterPolicy: WHAT the role is allowed to do.
data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json

  tags = {
    Name = "${var.cluster_name}-cluster-role"
  }
}

# AWS-managed policy granting EKS the permissions it needs to operate the
# control plane against your VPC.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ---- 3b EKS cluster (managed control plane) --------------------------------
# Provisioning this creates the AWS-managed control plane: API servers, etcd,
# scheduler, controller-manager -- all run by AWS across 3 AZs, outside your
# VPC. This is the "3 control nodes" equivalent, fully managed. Takes ~10 min.
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  # Where EKS injects the control-plane <->    networking ENIs. We give it
  # the private subnets (workers live here); EKS spreads its cross-AZ ENIs
  # across them. Listing 3 AZs satisfies the >= 2 AZ requirement.
  vpc_config {
    subnet_ids = aws_subnet.private[*].id

    # Endpoint access:
    #   public  = true  -> you can run kubectl from your laptop over the internet
    #   private = true  -> in-VPC traffic (nodes) reaches the API via a private
    #                      endpoint, not out over the internet
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # Use the modern EKS access-entry system (Step 5) instead of the legacy
  # aws-auth ConfigMap. API = access entries only; API_AND_CONFIG_MAP would
  # also honor the old ConfigMap.
  access_config {
    authentication_mode = "API"
  }

  # Ship control-plane component logs to CloudWatch. Useful for learning and
  # debugging (e.g. seeing authenticator/audit decisions). Small ongoing cost.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Ensure the role's policy is attached before the cluster tries to use it,
  # otherwise creation can race and fail with a permissions error.
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name = var.cluster_name
  }
}


# ---- 5) Admin access entry --------------------------------------------------
# Maps your IAM (SSO) role into the cluster and grants it cluster-admin, using
# the modern access-entry API (authentication_mode = "API" above).
#
# Two resources:
#   - access_entry: recognizes the IAM role as a principal in the cluster.
#     By itself it grants NO permissions (default-deny).
#   - access_policy_association: attaches the AWS-managed ClusterAdmin access
#     policy, scoped cluster-wide -> effectively binds it to cluster-admin.
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  # The entry must exist before a policy can be associated to it.
  depends_on = [aws_eks_access_entry.admin]
}
