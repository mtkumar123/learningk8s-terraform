# =============================================================================
# IAM: SEPARATE roles for control plane vs workers (least privilege).
#
# Both roles get SSM shell access (AmazonSSMManagedInstanceCore). Beyond that:
#   - Control plane: read + write the join-command SSM parameter
#     (it runs `kubeadm init` then publishes the join command).
#   - Worker: read-only the join-command parameter (it polls, then joins).
#
# Each role is wrapped in its own instance profile (EC2 attaches a profile,
# not a role directly).
# =============================================================================

# Look up our account ID dynamically so we don't hardcode it in ARNs.
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Control-plane role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "control_plane" {
  name = "${var.cluster_name}-control-plane-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-control-plane-role" }
}

resource "aws_iam_role_policy_attachment" "cp_ssm" {
  role       = aws_iam_role.control_plane.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read + write BOTH join parameters (worker join + control-plane join).
# The primary writes both; all control planes (sharing this role) can read them.
resource "aws_iam_role_policy" "cp_join_param" {
  name = "join-command-rw"
  role = aws_iam_role.control_plane.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:PutParameter", "ssm:GetParameter"]
      Resource = [
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.join_command_param_name}",
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.cp_join_command_param_name}"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.cluster_name}-control-plane-profile"
  role = aws_iam_role.control_plane.name
}

# ---------------------------------------------------------------------------
# Worker role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "worker" {
  name = "${var.cluster_name}-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.cluster_name}-worker-role" }
}

resource "aws_iam_role_policy_attachment" "worker_ssm" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read-only the join-command parameter.
resource "aws_iam_role_policy" "worker_join_param" {
  name = "join-command-ro"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.join_command_param_name}"
    }]
  })
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.cluster_name}-worker-profile"
  role = aws_iam_role.worker.name
}
