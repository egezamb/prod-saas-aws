resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = local.name }
}

# Postgres' own log (errors, slow statements) in CloudWatch, next to the app's. Declared here so
# Terraform owns its retention: RDS would otherwise create it on first export, kept forever.
resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/instance/${local.name}/postgresql"
  retention_in_days = 30
  tags              = { Name = "${local.name}-postgresql" }
}

resource "aws_db_parameter_group" "main" {
  name   = local.name
  family = "postgres16"

  # A dynamic parameter: a new value applies without a reboot.
  parameter {
    name  = "log_min_duration_statement"
    value = var.db_slow_query_ms
  }

  tags = { Name = local.name }
}

resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 3 # storage autoscaling headroom
  storage_type          = "gp3"
  storage_encrypted     = true

  # Lets the app or an operator sign in with a short-lived IAM token instead of the stored password
  # (rds-db:connect). Nothing changes until a database user is granted rds_iam; that user then
  # signs in with tokens only, so move callers over one user at a time.
  iam_database_authentication_enabled = true
  copy_tags_to_snapshot               = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  # On an existing instance, moving to this parameter group takes one reboot ("pending-reboot").
  parameter_group_name            = aws_db_parameter_group.main.name
  enabled_cloudwatch_logs_exports = ["postgresql"]
  publicly_accessible             = false # private subnets only; said explicitly, not left to the API default
  multi_az                        = var.db_multi_az

  backup_retention_period = 7
  # One switch for real production: refuse deletes, and keep a final snapshot if it is deleted anyway.
  deletion_protection       = var.db_protect
  skip_final_snapshot       = !var.db_protect
  final_snapshot_identifier = var.db_protect ? "${local.name}-final" : null
  apply_immediately         = true

  tags = { Name = local.name }

  depends_on = [aws_cloudwatch_log_group.rds] # the group exists before RDS starts exporting
}
