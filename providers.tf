# Configures the AWS provider declared in versions.tf.
#
# region and profile come from variables so the account-specific value
# (your SSO profile) lives only in terraform.tfvars, which is gitignored.
# If the SSO session has expired, run:  aws sso login --profile <your-profile>
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}
