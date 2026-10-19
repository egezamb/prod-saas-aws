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

run "waf_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.main) == 0 && length(aws_wafv2_web_acl_association.alb) == 0
    error_message = "No web ACL unless enable_waf is set."
  }
}

run "enable_waf_puts_a_web_acl_in_front_of_the_alb" {
  command = plan

  variables {
    enable_waf     = true
    waf_rate_limit = 500
  }

  assert {
    condition     = length(aws_wafv2_web_acl.main) == 1 && length(aws_wafv2_web_acl_association.alb) == 1
    error_message = "enable_waf must create the web ACL and attach it to the ALB."
  }
  assert {
    condition     = aws_wafv2_web_acl.main[0].scope == "REGIONAL" && length(aws_wafv2_web_acl.main[0].rule) == 4
    error_message = "The web ACL must be regional (an ALB) with the three managed rule groups and the rate limit."
  }
  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.main[0].rule :
      length(r.statement[0].rate_based_statement) == 1 && r.statement[0].rate_based_statement[0].limit == 500
    ])
    error_message = "The rate-based rule must use waf_rate_limit."
  }
}

run "waf_rate_limit_below_the_aws_minimum_is_refused" {
  command = plan

  variables {
    enable_waf     = true
    waf_rate_limit = 5
  }

  expect_failures = [var.waf_rate_limit]
}

run "an_outage_alarms_even_when_no_request_reaches_the_app" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.alb_elb_5xx.metric_name == "HTTPCode_ELB_5XX_Count" &&
      aws_cloudwatch_metric_alarm.alb_elb_5xx.namespace == "AWS/ApplicationELB"
    )
    error_message = "The ALB's own 5xx (no healthy target, dropped or timed-out connections) must have an alarm."
  }
}

run "no_healthy_target_alarms_without_traffic" {
  command = plan

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.no_healthy_targets.metric_name == "HealthyHostCount" &&
      aws_cloudwatch_metric_alarm.no_healthy_targets.treat_missing_data == "breaching"
    )
    error_message = "No healthy target must alarm, and a missing data point (nothing registered) must count as down."
  }
}

run "every_alarm_notifies_the_topic_and_back_to_ok" {
  command = plan

  assert {
    condition = alltrue([
      for a in [
        aws_cloudwatch_metric_alarm.alb_5xx,
        aws_cloudwatch_metric_alarm.alb_elb_5xx,
        aws_cloudwatch_metric_alarm.no_healthy_targets,
        aws_cloudwatch_metric_alarm.ecs_cpu,
        aws_cloudwatch_metric_alarm.rds_storage,
      ] : length(a.alarm_actions) == 1 && length(a.ok_actions) == 1
    ])
    error_message = "Every alarm must publish to the alarm topic when it fires and when it clears."
  }
  assert {
    condition     = aws_kms_key.alarms.enable_key_rotation && length(aws_sns_topic_subscription.alarm_email) == 0
    error_message = "The topic's key must rotate, and no subscriber is created without alarm_email."
  }
}

run "alarm_email_subscribes_to_the_topic" {
  command = plan

  variables {
    alarm_email = "oncall@example.com"
  }

  assert {
    condition = (
      length(aws_sns_topic_subscription.alarm_email) == 1 &&
      aws_sns_topic_subscription.alarm_email[0].protocol == "email" &&
      aws_sns_topic_subscription.alarm_email[0].endpoint == "oncall@example.com"
    )
    error_message = "alarm_email must subscribe that address to the alarm topic."
  }
}

run "alarm_email_that_is_not_an_address_is_refused" {
  command = plan

  variables {
    alarm_email = "oncall"
  }

  expect_failures = [var.alarm_email]
}
