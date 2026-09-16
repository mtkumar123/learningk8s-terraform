# =============================================================================
# Security group for all Kubernetes cluster nodes (control plane + workers).
#
# Design: ONE shared "cluster" SG that every node belongs to, with a
# self-referencing rule allowing all traffic BETWEEN members. This covers
# every node-to-node port Kubernetes and the CNI need (6443, etcd 2379-2380,
# kubelet 10250, scheduler, controller, and all pod-to-pod CNI traffic)
# without enumerating them, and keeps working when we pick a CNI later.
#
# This is the same coarse "trust boundary" pattern EKS and most self-managed
# clusters use at the AWS layer; fine-grained pod segmentation is done later
# with Kubernetes Network Policies (a future lesson), not with this SG.
# =============================================================================

# ---- The cluster security group (an empty container of rules for now) -------
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "All Kubernetes cluster nodes (control plane + workers)"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                                        = "${var.cluster_name}-cluster-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ---- Rule 1: allow ALL traffic BETWEEN members of this SG -------------------
# WHO  = referenced_security_group_id = this SG itself (self-reference)
# WHAT = ip_protocol "-1" = every protocol and every port
# So: any node in cluster-sg may talk to any other node in cluster-sg, freely.
# Note: the source is SG MEMBERSHIP, not an IP range -- there is deliberately
# no cidr here (that would open it to the whole internet).
resource "aws_vpc_security_group_ingress_rule" "cluster_internal" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
  description                  = "Allow all traffic between cluster nodes"
}

# ---- Rule 3: allow API server (6443) from the NLB's security group ----------
# The control-plane NLB has its own SG (nlb-sg), which is NOT a member of the
# cluster SG, so Rule 1 (self-reference) doesn't cover it. Allow 6443 from the
# NLB SG so its health checks and forwarded API traffic reach the API server.
resource "aws_vpc_security_group_ingress_rule" "api_from_nlb" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.nlb.id
  from_port                    = 6443
  to_port                      = 6443
  ip_protocol                  = "tcp"
  description                  = "API server (6443) from the control-plane NLB"
}

# ---- Rule 2: allow ALL outbound to anywhere ---------------------------------
# Nodes need egress via the NAT Gateway for: container image pulls
# (registry.k8s.io etc.), OS package installs, and the SSM agent's outbound
# connection (which is what makes SSM shell access work with NO inbound rule).
# Here the DESTINATION really is "the whole internet", so 0.0.0.0/0 is correct.
resource "aws_vpc_security_group_egress_rule" "cluster_egress" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound (image pulls, packages, SSM)"
}
