# Cost — honest monthly estimate

No hand-waving. This is roughly what the default configuration costs in
`eu-central-1`, idle-to-light traffic, on-demand pricing (July 2026). Prices vary
by region and change over time — treat it as an order of magnitude, not a quote.

| Component | Default | ~Monthly (USD) | Notes |
|---|---:|---:|---|
| **NAT Gateway** | 1 × | **~$32** + data | The biggest line item. Bills hourly even at zero traffic. |
| **Application Load Balancer** | 1 × | **~$16** + LCU | Also hourly, always-on. |
| **RDS PostgreSQL** | `db.t4g.micro`, 20 GB gp3, single-AZ | **~$13** | Graviton, cheapest sane option. `db_multi_az = true` adds a standby in a second AZ and roughly doubles this line. |
| **ECS Fargate** | 2 tasks × 0.25 vCPU / 0.5 GB | **~$13** | Scales up under load (2→6). |
| **ECR / SSM / CloudWatch / KMS / logs** | — | **~$3–6** | Storage, a few metrics and alarms, and the alarm topic's KMS key ($1). SNS email is free for the first 1,000 a month. |
| **AWS WAF** (opt-in) | off; `enable_waf = true` | **~$9** + $0.60 per million requests | A web ACL ($5) with four rules ($1 each): three AWS managed rule groups and a per-IP rate limit. Not in the total. |
| **Total** | | **≈ $75–80 / month** | Dominated by NAT + ALB (~$48 of it). |

## The honest takeaway

**~$48 of the ~$78 is NAT Gateway + ALB — fixed hourly cost, before you serve a
single request.** That's the price of the "textbook production" shape. If you're
running a demo or a tiny SaaS, you don't need to pay it.

## How to make it much cheaper

| Change | Saves | Trade-off |
|---|---:|---|
| **Drop the NAT gateway** — run Fargate tasks in public subnets with a tight SG, or add **VPC endpoints** for ECR/S3/CloudWatch | **~$32/mo** | Slightly less "private"; VPC endpoints have their own (small) cost. |
| **Fargate Spot** for the service | up to ~70% of compute | Tasks can be reclaimed; fine for stateless web tiers. |
| **Replace ALB** with a single EC2 + Caddy (the [DEPOS pattern](https://github.com/egezamb/cloud-infrastructure)) | **~$16/mo** | You manage the box; no managed LB features. |
| **Stop `desired_count` to 1** off-peak / dev | ~$6/mo | Less headroom. |

A cost-optimized variant (no NAT, Fargate Spot, 1 task) lands around
**~$30–35/month** — most of it the unavoidable ALB + RDS.

> A big reason to show this file: knowing *where the money goes* and how to cut it
> is a real part of the DevOps job, not an afterthought.
