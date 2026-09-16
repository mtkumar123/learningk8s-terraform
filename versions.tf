# Pins the Terraform core version and the providers this project uses, so that
# everyone (and every future run) resolves the same tooling. The AWS provider
# 5.x line has full support for EKS access entries, which we rely on later.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}
