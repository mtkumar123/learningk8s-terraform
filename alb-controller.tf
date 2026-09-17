# =============================================================================
# AWS Load Balancer Controller: watches Ingress/Service objects and provisions
# ALBs/NLBs. Its pods call the AWS ELB/EC2 APIs, so (like the EBS CSI driver)
# they get AWS permissions via EKS Pod Identity.
#
# Built in sub-steps:
#   7a) IAM role + policy for the controller   <-- this file, so far
#   7b) Install the controller (Helm) + Pod Identity association
#   7c) Ingress (provisions the public ALB)
#   7d) Update BASE_URL to the ALB DNS
#
# The controller itself is installed out-of-band via Helm (see 7b notes),
# consistent with how we manage other in-cluster components. Terraform owns the
# AWS-side IAM + association.
# =============================================================================

# ---- 7a) IAM role + policy --------------------------------------------------
# Custom policy from the official controller repo (downloaded to
# iam/alb-controller-iam-policy.json). It's large and version-tracked, so we
# load it from file rather than inline it.
resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller-policy"
  description = "Permissions for the AWS Load Balancer Controller"
  policy      = file("${path.module}/iam/alb-controller-iam-policy.json")
}

# Pod Identity trust: same pattern as the EBS CSI role -- the Pod Identity
# service assumes this, and the association (7b) scopes it to the controller's
# ServiceAccount.
data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json

  tags = {
    Name = "${var.cluster_name}-alb-controller-role"
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}


# ---- 7b) Pod Identity association -------------------------------------------
# Binds the controller's ServiceAccount (created by the Helm chart, named
# aws-load-balancer-controller in kube-system) to the IAM role above, so the
# controller pods receive ELB/EC2 permissions at runtime. Matches by name, so
# it's fine for this to exist before Helm creates the SA.
resource "aws_eks_pod_identity_association" "alb_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.alb_controller.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
