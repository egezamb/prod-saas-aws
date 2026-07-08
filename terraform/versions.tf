terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state is intentionally left to the user — uncomment and configure an
  # S3 backend (with DynamoDB locking) before using this beyond a single machine.
  # backend "s3" {}
}
