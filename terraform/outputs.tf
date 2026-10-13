output "app_url" {
  description = "Public URL of the load balancer."
  value       = local.tls_enabled ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "Push your container image here, then re-apply."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "rds_endpoint" {
  description = "RDS endpoint (reachable only from ECS tasks)."
  value       = aws_db_instance.main.address
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "github_deploy_role_arn" {
  description = "Set this as the AWS_ROLE_ARN secret of the GitHub repository to enable the deploy workflow."
  value       = aws_iam_role.deploy.arn
}
