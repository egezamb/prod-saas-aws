provider "aws" {
  region = var.region

  # Every resource gets these tags — cost allocation, ownership, and cleanup.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
