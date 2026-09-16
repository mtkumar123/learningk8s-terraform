# Template for terraform.tfvars. Copy this file to terraform.tfvars and fill
# in your own values:
#
#   cp example.tfvars terraform.tfvars
#
# terraform.tfvars is gitignored; this template IS committed (see the
# !example.tfvars rule in .gitignore).

# AWS CLI/SSO profile Terraform authenticates with.
aws_profile = "AdministratorAccess-XXXXXXXXXXXX"

# Everything else has sensible defaults in variables.tf. Override here only
# if you want to change region, instance types, counts, CIDRs, etc. e.g.:
# region               = "eu-west-1"
# control_plane_count  = 3
# worker_count         = 2
