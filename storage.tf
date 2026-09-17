# =============================================================================
# Persistent storage prerequisites: EBS CSI driver so PersistentVolumeClaims
# can be dynamically backed by EBS volumes. The driver's controller pods call
# the EC2 API, so they get AWS permissions via EKS Pod Identity.
#
# Built in sub-steps:
#   6a) Pod Identity Agent add-on   <-- this file, so far
#   6b) IAM role for the EBS CSI driver
#   6c) EBS CSI driver add-on + Pod Identity association
#   6d) gp3 StorageClass (default)
# =============================================================================

# ---- 6a) Pod Identity Agent add-on ------------------------------------------
# A DaemonSet (one pod per node) that hands EKS Pod Identity credentials to
# pods on that node. Required before any Pod Identity association takes effect.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"

  # Ensure at least one node exists to schedule the DaemonSet onto.
  depends_on = [aws_eks_node_group.main]
}


# ---- 6b) IAM role for the EBS CSI driver ------------------------------------
# The driver's controller pods assume this role (via Pod Identity) to call the
# EC2 API and create/attach/detach EBS volumes.
#
# Trust principal is pods.eks.amazonaws.com (the Pod Identity service), and it
# needs BOTH sts:AssumeRole and sts:TagSession -- Pod Identity tags the session
# with the cluster/namespace/service-account, so TagSession is required.
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json

  tags = {
    Name = "${var.cluster_name}-ebs-csi-role"
  }
}

# AWS-managed policy with exactly the EBS permissions the driver needs
# (CreateVolume, AttachVolume, DeleteVolume, CreateSnapshot, etc.).
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


# ---- 6c) EBS CSI driver add-on + Pod Identity association -------------------
# The add-on installs the driver (ebs-csi-controller Deployment + ebs-csi-node
# DaemonSet) and creates the ebs-csi-controller-sa ServiceAccount in
# kube-system. The association then binds that ServiceAccount to the IAM role
# from 6b, so the controller pods receive EBS permissions at runtime.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "aws-ebs-csi-driver"

  # Wait for the driver + the association's prerequisites to exist first.
  depends_on = [
    aws_eks_node_group.main,
    aws_eks_addon.pod_identity_agent,
  ]
}

# Maps the driver's ServiceAccount -> the EBS IAM role. This is the object that
# actually scopes the role to exactly one ServiceAccount (see 6b discussion).
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
