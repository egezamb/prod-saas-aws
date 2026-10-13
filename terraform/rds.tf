resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = local.name }
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
  multi_az               = false # single-AZ to keep cost down; flip to true for real prod HA

  backup_retention_period = 7
  # One switch for real production: refuse deletes, and keep a final snapshot if it is deleted anyway.
  deletion_protection       = var.db_protect
  skip_final_snapshot       = !var.db_protect
  final_snapshot_identifier = var.db_protect ? "${local.name}-final" : null
  apply_immediately         = true

  tags = { Name = local.name }
}
