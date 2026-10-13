# ALB: open to the internet on 80/443.
resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB — public HTTP/HTTPS ingress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-alb" }
}

# ECS tasks: only reachable from the ALB, on the container port.
resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs"
  description = "ECS tasks — ingress only from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  tags = { Name = "${local.name}-ecs" }
}

# RDS: only reachable from the ECS tasks, on the Postgres port.
resource "aws_security_group" "rds" {
  name        = "${local.name}-rds"
  description = "RDS — ingress only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = { Name = "${local.name}-rds" }
}

# Egress is narrowed to what each tier needs. The rules are separate resources because the ALB and
# ECS groups refer to each other, which inline rules cannot do without a cycle. Terraform removes
# the allow-all egress rule AWS adds to a new group.

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To the ECS tasks, on the container port"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = aws_security_group.ecs.id
}

# HTTPS through the NAT gateway: ECR image pulls, Secrets Manager, CloudWatch Logs. An app that
# calls other ports outside needs its own rule here.
# trivy:ignore:AWS-0104 ECR, Secrets Manager and CloudWatch through the NAT gateway (no VPC endpoints).
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS to AWS APIs and the internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_rds" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Postgres on RDS"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}
