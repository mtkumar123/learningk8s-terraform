# Dynamically look up the latest Amazon Linux 2023 AMI for arm64 (Graviton).
#
# A `data` source READS from AWS (creates nothing). This resolves to the newest
# matching image in our region at apply time, so we never hardcode a
# region-specific, soon-stale AMI ID.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"] # trusted Amazon-owned images only

  # Pin the kernel line explicitly. AL2023 arm64 images always carry a
  # -kernel-X.Y- segment, and multiple kernels share the same release date,
  # so without pinning, most_recent picks arbitrarily. 6.12 is a mature,
  # stable line (not the brand-new 6.18).
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.12-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  # Only fully-available images (excludes any in a pending/failed state).
  filter {
    name   = "state"
    values = ["available"]
  }
}
