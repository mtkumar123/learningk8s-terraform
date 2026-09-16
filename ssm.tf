# =============================================================================
# SSM Parameter Store entry used as the "blackboard" for cluster join.
#
# Flow:
#   1. Terraform creates this parameter with the placeholder "pending".
#   2. The control plane's user_data runs `kubeadm init`, generates a join
#      command (`kubeadm token create --print-join-command`), and OVERWRITES
#      this parameter's value with the real command.
#   3. Worker user_data polls this parameter until it's no longer "pending",
#      then runs `kubeadm join`.
#
# ignore_changes = [value]: Terraform owns the parameter's EXISTENCE (so it's
# cleanly destroyed), but the control plane owns its VALUE at runtime. Without
# this, a later `terraform apply` would reset the real join command back to
# "pending" and break future worker joins.
# =============================================================================
resource "aws_ssm_parameter" "join_command" {
  name  = var.join_command_param_name
  type  = "String"
  value = "pending" # placeholder; overwritten by the control plane at boot

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "${var.cluster_name}-join-command"
  }
}

# Control-plane join command (includes --certificate-key). Published by the
# PRIMARY control plane; polled by the secondary control planes to join as
# additional control planes. More sensitive than the worker token (carries the
# cert key), and kubeadm expires the cert key after ~2h by default.
resource "aws_ssm_parameter" "cp_join_command" {
  name  = var.cp_join_command_param_name
  type  = "String"
  value = "pending" # placeholder; overwritten by the primary control plane at boot

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Name = "${var.cluster_name}-cp-join-command"
  }
}
