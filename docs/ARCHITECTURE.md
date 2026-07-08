# Architecture

## Request path

1. A client hits the **ALB** on 80/443 (public subnets, 2 AZs).
2. If a TLS cert is configured, 80 redirects to 443; the listener forwards to the
   **target group** on the container port.
3. The target group routes to healthy **ECS Fargate** tasks (private subnets),
   registered by IP. Health is the app's `/health` endpoint.
4. The app talks to **RDS PostgreSQL** over 5432 — allowed only from the ECS
   security group. RDS has no public access.
5. Outbound traffic from tasks (image pulls, external APIs) leaves through the
   **NAT gateway**.

## Layers

| Layer | Resource | Where |
|---|---|---|
| Edge | Application Load Balancer + listeners | public subnets |
| Compute | ECS Fargate service + task definition + autoscaling | private subnets |
| Data | RDS PostgreSQL + subnet group | private subnets |
| Registry | ECR (scan-on-push, lifecycle keep-10) | regional |
| Secrets | SSM Parameter Store (SecureString) | regional |
| Identity | IAM execution role (pull + logs + SSM read) & task role | — |
| Telemetry | CloudWatch logs, dashboard, alarms | regional |

## Security groups (the chain)

```
Internet ──(80/443)──► alb-sg ──(:8000)──► ecs-sg ──(:5432)──► rds-sg
```

Each tier only accepts traffic from the tier in front of it — no security group
is open to `0.0.0.0/0` except the ALB.

## Deploy flow (CI/CD)

- **PR** → `terraform fmt/validate` + app tests + docker build (CI).
- **Merge to main** (app changes) → build image, push to ECR, `ecs update-service
  --force-new-deployment` (CD, via GitHub OIDC — no static AWS keys). Skips
  cleanly if `AWS_ROLE_ARN` isn't set.

## HA and scaling posture

- **2 AZs** for the network and target group; ECS spreads tasks across them.
- **Autoscaling** 2→6 tasks on CPU.
- RDS is **single-AZ by default** (cost) — flip `multi_az = true` for real HA.
