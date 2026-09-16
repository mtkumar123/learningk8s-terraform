# =============================================================================
# Cluster nodes (self-forming):
#
#   control-plane : single aws_instance. user_data runs kubeadm init, installs
#                   Calico, and publishes the join command to SSM.
#   workers       : launch template + Auto Scaling Group (min=2/desired=2/max=4).
#                   user_data polls SSM for the join command, then joins.
#
# All nodes: AL2023 arm64, t4g.medium, no public IP, cluster SG, 20 GB gp3.
# Access via SSM only.
# =============================================================================

# ---- Control plane (single, self-initializing) -----------------------------
resource "aws_instance" "control_plane" {
  count                  = var.control_plane_count
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.control_plane_instance_type
  subnet_id              = aws_subnet.private[count.index].id # one per AZ
  vpc_security_group_ids = [aws_security_group.cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.control_plane.name

  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/control-plane-userdata.sh.tftpl", {
    kubernetes_version         = var.kubernetes_version
    pod_cidr                   = var.pod_cidr
    region                     = var.region
    join_command_param_name    = var.join_command_param_name
    cp_join_command_param_name = var.cp_join_command_param_name
    calico_version             = var.calico_version
    nlb_endpoint               = aws_lb.control_plane.dns_name
    is_primary                 = count.index == 0
    node_name                  = "control-plane-${count.index + 1}"
    # VPC resolver = VPC CIDR base + 2 (e.g. 10.0.0.0/16 -> 10.0.0.2). Added as a
    # second nameserver on calico-node so install-cni can resolve the NLB FQDN
    # via the VPC resolver (no CNI needed), instead of only CoreDNS ClusterIP.
    vpc_dns_ip = cidrhost(var.vpc_cidr, 2)
  })

  # user_data only runs at first boot, so a changed script must REPLACE the
  # instance (destroy + recreate) to actually take effect -- otherwise the
  # self-forming init would never run on an already-booted node.
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.node_root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  # The SSM parameters must exist before the control plane overwrites them.
  depends_on = [aws_ssm_parameter.join_command, aws_ssm_parameter.cp_join_command]

  tags = {
    Name                                        = "${var.cluster_name}-control-plane-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "node-role"                                 = "control-plane"
  }
}

# Register each control plane into the NLB target group on 6443.
resource "aws_lb_target_group_attachment" "control_plane" {
  count            = var.control_plane_count
  target_group_arn = aws_lb_target_group.control_plane.arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

# ---- Worker launch template (blueprint for ASG-launched workers) -----------
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.cluster_name}-worker-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.worker_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  vpc_security_group_ids = [aws_security_group.cluster.id]

  user_data = base64encode(templatefile("${path.module}/templates/worker-userdata.sh.tftpl", {
    kubernetes_version      = var.kubernetes_version
    region                  = var.region
    join_command_param_name = var.join_command_param_name
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.node_root_volume_size
      volume_type = "gp3"
      encrypted   = true
    }
  }

  # Tags applied to the launch template resource itself.
  tags = {
    Name = "${var.cluster_name}-worker-lt"
  }
}

# ---- Worker Auto Scaling Group ---------------------------------------------
# Spread across both private subnets (AWS balances instances across the AZs).
# Scale by changing desired_capacity (up to max_size).
resource "aws_autoscaling_group" "worker" {
  name                = "${var.cluster_name}-worker-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  min_size            = 2
  desired_capacity    = 2
  max_size            = 4

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  # Tags propagated to each launched instance.
  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "shared"
    propagate_at_launch = true
  }
  tag {
    key                 = "node-role"
    value               = "worker"
    propagate_at_launch = true
  }

  # Ensure the control-plane instances at least exist before workers launch.
  # (Actual join-command availability is handled by the worker poll loop, which
  # waits on the SSM parameter regardless of Terraform ordering.)
  depends_on = [aws_instance.control_plane]
}
