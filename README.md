# Production SaaS on AWS — Terraform reference

![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate%20%C2%B7%20RDS%20%C2%B7%20ALB-FF9900?logo=amazonaws&logoColor=white)
![CI](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

A **complete, opinionated reference** for running a containerized web app in
production on AWS — the whole thing an engineer wires up for a real SaaS, as
readable Terraform you can `apply` in your own account. Networking, container
platform, database, load balancer, CI/CD, secrets, autoscaling, and
observability — plus an **honest monthly cost breakdown** (see [docs/COST.md](docs/COST.md)).

Not "hello world," not a 3,000-star framework — a **real, end-to-end estate**
you can read top-to-bottom and learn the actual job from.

---

## Architecture

```
                 Internet
                    │  HTTP/HTTPS
                    ▼
        ┌───────────────────────┐        public subnets (2 AZ)
        │  Application Load      │◄───────────────────────────────
        │  Balancer (+ ACM TLS)  │
        └───────────┬───────────┘
                    │  forward :8000
                    ▼
        ┌───────────────────────┐        private subnets (2 AZ)
        │  ECS Fargate service   │  ──►  autoscaling (CPU target 60%, 2→6 tasks)
        │  (containerized app)   │
        └───────────┬───────────┘
                    │  postgres :5432 (SG-locked)
                    ▼
        ┌───────────────────────┐
        │  RDS PostgreSQL 16     │  encrypted, 7-day backups, private
        └───────────────────────┘

  ECR ── image registry (scan-on-push, keep-last-10)
  SSM Parameter Store ── DB creds as SecureString → injected into tasks
  CloudWatch ── logs + dashboard + alarms → SNS (encrypted) → email / Slack / pager
  IAM ── least-privilege task & execution roles
```

Every box is Terraform in [`terraform/`](terraform/). The app in [`app/`](app/)
is a tiny FastAPI service — deliberately minimal, because the point is the
infrastructure around it.

## What this demonstrates

- **Cloud-native compute** — ECS Fargate (no servers to manage), rolling deploys,
  target-tracking **autoscaling**.
- **Real networking** — VPC across 2 AZs, public/private subnet split, the app and
  database with **no public exposure**, security groups chained ALB → ECS → RDS.
- **Managed data** — RDS PostgreSQL, encrypted, automated backups, private.
- **Secrets done right** — generated in Terraform, stored as **SSM SecureString**,
  injected into containers at runtime — never in code, image, or task definition.
- **CI/CD** — GitHub Actions: `terraform validate` + app tests on every PR; build →
  ECR → **roll ECS** on merge (OIDC, no long-lived keys). Deploy **skips safely**
  until creds are configured.
- **Observability** — CloudWatch log group, a one-screen dashboard, and alarms
  that reach a person through an encrypted SNS topic: app 5xx, the ALB's own 5xx,
  no healthy task (fires with zero traffic), ECS CPU, RDS storage.
- **Cost-awareness** — a transparent [cost breakdown](docs/COST.md) and how to cut it.

## Quick start

```bash
cd terraform
terraform init
terraform apply                      # creates the estate (ECR empty for now)

# build & push the app image to the ECR repo Terraform just made
cd ../app
aws ecr get-login-password --region eu-central-1 \
  | docker login --username AWS --password-stdin "$(cd ../terraform && terraform output -raw ecr_repository_url | cut -d/ -f1)"
docker build -t "$(cd ../terraform && terraform output -raw ecr_repository_url):latest" .
docker push "$(cd ../terraform && terraform output -raw ecr_repository_url):latest"

cd ../terraform
# The first deployment found no image and stopped (the circuit breaker has nothing to roll back to),
# so start a new one now that the image exists.
aws ecs update-service --cluster prod-saas-prod --service prod-saas-prod --force-new-deployment
terraform output app_url             # open it once the service is stable
```

From then on, deploys go through GitHub Actions: set the `github_deploy_role_arn` output as the
repository secret `AWS_ROLE_ARN`, and every merge to `main` that changes `app/` ships a new image.

TLS is optional: set `-var certificate_arn=<acm-arn>` and the ALB serves HTTPS and
redirects HTTP→HTTPS. Leave it empty for plain HTTP (fine for a demo).

**Tear down:** `terraform destroy`. See [docs/COST.md](docs/COST.md) — the NAT
gateway and ALB bill by the hour whether or not you get traffic.

## Repo layout

```
prod-saas-aws/
├── terraform/     # the estate: network · ecs · rds · alb · ecr · iam · secrets · observability
├── app/           # sample FastAPI app + Dockerfile + test
├── .github/       # CI (validate + test) and CD (build → ECR → roll ECS)
└── docs/          # ARCHITECTURE · DECISIONS · COST
```

## Docs

- [Architecture](docs/ARCHITECTURE.md) — request path, layers, why this shape
- [Decisions](docs/DECISIONS.md) — Fargate vs EC2, single NAT, secrets, TLS…
- [Cost](docs/COST.md) — honest ~monthly breakdown + how to make it cheaper

## Not production-hardened out of the box

This is a **reference** — clear over maximal. Before real production, turn on:

- `db_multi_az` and `db_protect` for RDS (a standby in a second AZ; deletion protection and a final snapshot);
- `enable_waf` for AWS WAF in front of the ALB;
- `alarm_email` so the alarms reach someone (or subscribe Slack or a pager to the `alarm_topic_arn` output);
- remote state in S3 with `use_lockfile` (see [Decisions](docs/DECISIONS.md));
- per-environment workspaces.

`terraform test` (mocked providers, no AWS account) checks what each switch does.

## License

MIT — clone, read, adapt, learn from it.
