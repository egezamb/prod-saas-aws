# DB password is generated here and stored encrypted in SSM — never in code,
# never in plan output beyond the write, and injected into the task at runtime.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${local.name}/db_password"
  type  = "SecureString"
  value = random_password.db.result
  tags  = { Name = "${local.name}-db-password" }
}

resource "aws_ssm_parameter" "database_url" {
  name = "/${local.name}/database_url"
  type = "SecureString"
  value = format(
    "postgresql://%s:%s@%s:5432/%s",
    var.db_username,
    random_password.db.result,
    aws_db_instance.main.address,
    var.db_name,
  )
  tags = { Name = "${local.name}-database-url" }
}
