# Plan-only tests with mocked providers: no AWS account or credentials needed.
#   cd terraform && terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

mock_provider "random" {}

run "defaults_keep_the_database_private_and_encrypted" {
  command = plan

  assert {
    condition     = aws_db_instance.main.storage_encrypted && !aws_db_instance.main.publicly_accessible
    error_message = "RDS must be encrypted and not publicly accessible."
  }
  assert {
    condition     = !aws_db_instance.main.deletion_protection && aws_db_instance.main.skip_final_snapshot
    error_message = "By default the demo stack must be destroyable in one step (db_protect = false)."
  }
  assert {
    condition     = !aws_db_instance.main.multi_az
    error_message = "The demo stack runs RDS in one AZ by default (db_multi_az = false)."
  }
}

run "db_multi_az_adds_a_standby" {
  command = plan

  variables {
    db_multi_az = true
  }

  assert {
    condition     = aws_db_instance.main.multi_az
    error_message = "db_multi_az must run RDS with a Multi-AZ standby."
  }
}

run "db_protect_refuses_deletes_and_keeps_a_final_snapshot" {
  command = plan

  variables {
    db_protect = true
  }

  assert {
    condition     = aws_db_instance.main.deletion_protection && !aws_db_instance.main.skip_final_snapshot
    error_message = "db_protect must turn on deletion protection and the final snapshot."
  }
}
