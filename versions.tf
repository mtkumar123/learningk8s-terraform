terraform {
  # Minimum Terraform CLI version this project supports.
  # You're on 1.16.1; anything >= 1.5 works.
  required_version = ">= 1.5"

  required_providers {
    # The AWS provider is the plugin that teaches Terraform how to talk
    # to the AWS APIs. "source" is where Terraform downloads it from
    # (the public registry), and "version" pins us to the 5.x line so
    # a future 6.x release can't silently change behavior under us.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
