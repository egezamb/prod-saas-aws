resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = 30
  tags              = { Name = local.name }
}

# --- Alarms: what a web service needs to page on ---

# 1. App is throwing 5xx (bad deploy / bug).
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_description   = "App returned >5 HTTP 5xx in a minute"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
  tags = { Name = "${local.name}-alb-5xx" }
}

# 2. The load balancer itself answers 5xx: 503 with no healthy target, 502 when a task drops the
# connection, 504 when it does not answer in time. These never reach the app, so the target 5xx
# alarm above stays quiet through a full outage.
resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx" {
  alarm_name          = "${local.name}-alb-elb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_description   = "The ALB returned >5 of its own 5xx (502/503/504) in a minute: tasks are down or not answering"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
  tags = { Name = "${local.name}-alb-elb-5xx" }
}

# 3. No healthy task behind the ALB. Unlike the 5xx alarms this does not need traffic, so a service
# that went down at night alarms before the first visitor finds it. Missing data counts as down:
# the metric is only reported while the target group has registered targets, and a service with no
# running task has none.
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name          = "${local.name}-no-healthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum" # every load balancer node sees no healthy target, not just one
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_description   = "No healthy ECS task behind the ALB for 2 minutes"
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
  tags = { Name = "${local.name}-no-healthy-targets" }
}

# 4. Sustained high CPU (under-provisioned / needs scaling attention).
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "ECS service CPU >80% for 3 minutes"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
  tags = { Name = "${local.name}-ecs-cpu-high" }
}

# 5. Database running low on storage.
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2000000000 # 2 GB in bytes
  treat_missing_data  = "notBreaching"
  alarm_description   = "RDS free storage below 2 GB"
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
  tags = { Name = "${local.name}-rds-low-storage" }
}

# --- Dashboard: one screen for the whole service ---
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB requests & 5xx"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "ECS CPU & memory"
          region = var.region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name]
          ]
          period = 60
          stat   = "Average"
        }
      }
    ]
  })
}
