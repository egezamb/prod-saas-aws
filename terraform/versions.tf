terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state is left to the user. Before using this beyond one machine, keep it in S3
  # (docs/DECISIONS.md). S3 locks the state itself with use_lockfile (generally available since
  # Terraform 1.11), so no DynamoDB table is needed:
  # backend "s3" {
  #   bucket       = "<your-state-bucket>"
  #   key          = "prod-saas-aws/terraform.tfstate"
  #   region       = "eu-central-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}
