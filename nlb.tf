# =============================================================================
# Security group for the control-plane NLB.
#   Inbound  : API server port (6443) from anywhere in the VPC.
#   Outbound : 6443 only to the node subnets (nothing else).
# =============================================================================
resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-nlb-sg"
  description = "Control-plane NLB: API traffic in from VPC, out to nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-nlb-sg"
  }
}

# Inbound: API server port from anywhere in the VPC.
resource "aws_vpc_security_group_ingress_rule" "nlb_api_in" {
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  description       = "API server (6443) inbound from within the VPC"
}

# Outbound: only to the node subnets on 6443 (one rule per private subnet).
resource "aws_vpc_security_group_egress_rule" "nlb_to_nodes" {
  count             = length(var.private_subnet_cidrs)
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = var.private_subnet_cidrs[count.index]
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  description       = "Forward API traffic to nodes in a private subnet"
}

# =============================================================================
# Internal Network Load Balancer (L4/TCP) fronting the 3 control-plane API
# servers on 6443. Provides the stable --control-plane-endpoint for HA.
# L4 (not ALB/L7) so it passes raw TLS through -- the API server does its own
# mTLS and must see the client certificate directly.
# =============================================================================

# The NLB itself: internal (private), spread across the 3 private subnets.
resource "aws_lb" "control_plane" {
  name               = "${var.cluster_name}-cp-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.nlb.id]

  tags = {
    Name = "${var.cluster_name}-cp-nlb"
  }
}

# Target group: the pool of control-plane API servers on 6443 (TCP).
resource "aws_lb_target_group" "control_plane" {
  name        = "${var.cluster_name}-cp-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  preserve_client_ip = "false"

  # Health check: is the API server answering on 6443?
  health_check {
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = {
    Name = "${var.cluster_name}-cp-tg"
  }
}

# Listener: accept TCP on 6443, forward to the target group.
resource "aws_lb_listener" "control_plane" {
  load_balancer_arn = aws_lb.control_plane.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.control_plane.arn
  }
}
