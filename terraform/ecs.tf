resource "aws_ecs_cluster" "main" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = local.name }
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = local.app_image
      essential = true
      # The app writes nothing to disk (PYTHONDONTWRITEBYTECODE is set in the image), so its
      # filesystem can be read-only: code that gets in cannot change the app or drop tools.
      readonlyRootFilesystem = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      # Non-secret config as plain env; secrets pulled from SSM at start.
      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "ENVIRONMENT", value = var.environment },
      ]
      secrets = [
        { name = "DATABASE_URL", valueFrom = aws_ssm_parameter.database_url.arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = { Name = local.name }
}

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # Let deploys settle before the ALB fails health checks.
  health_check_grace_period_seconds = 60

  # A deploy whose tasks keep failing stops on its own and rolls back to the last working revision,
  # instead of replacing healthy tasks with crashing ones until someone notices.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # The deploy workflow registers a new task definition revision for every image. Terraform must
  # not roll the service back to its own revision on the next apply.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = local.name }
}

# --- Autoscaling: target-track CPU at 60% between desired_count and 6 tasks ---
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 6
  min_capacity       = var.desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}

# Opt-in: also scale on ALB requests per task, for an I/O-bound workload that stays under the CPU
# target. Both policies drive the same scalable target; autoscaling takes the higher desired count,
# so the service scales on whichever pressure is greater. The resource label ties the metric to this
# ALB and target group (app/<lb>/<id>/targetgroup/<tg>/<id>).
resource "aws_appautoscaling_policy" "requests" {
  count              = var.requests_per_target > 0 ? 1 : 0
  name               = "${local.name}-requests"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value       = var.requests_per_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
