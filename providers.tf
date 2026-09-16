# Configures the AWS provider declared in versions.tf.
# region and profile are pulled from variables (see variables.tf) so the
# values live in one place and are easy to change.
#
# profile = var.aws_profile makes Terraform authenticate using the exact
# same AWS SSO profile your CLI uses. If the SSO session has expired,
# run:  aws sso login --profile <your-profile>   (see terraform.tfvars)
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}
