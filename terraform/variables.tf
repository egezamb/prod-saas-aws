variable "project" {
  type        = string
  default     = "prod-saas"
  description = "Project name — prefixes resource names and tags."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment name (prod, staging, dev)."
}

variable "region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC."
}

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of Availability Zones to spread across (2 = HA)."

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 for a highly-available setup."
  }
}

# --- Application ---
variable "container_image" {
  type        = string
  default     = ""
  description = "Container image to run. Leave empty to use the ECR repo created here (push an image first, then apply again)."
}

variable "container_port" {
  type        = number
  default     = 8000
  description = "Port the app listens on inside the container."
}

variable "desired_count" {
  type        = number
  default     = 2
  description = "Baseline number of running tasks (autoscaling adjusts up from here)."
}

variable "cpu" {
  type        = number
  default     = 256
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
}

variable "memory" {
  type        = number
  default     = 512
  description = "Fargate task memory in MiB."
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "HTTP path the ALB uses for target health checks."
}

# --- TLS (optional) ---
variable "certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN. If set, the ALB serves HTTPS and redirects HTTP→HTTPS. If empty, it serves plain HTTP (fine for a demo; add a cert for real use)."
}

# --- Database ---
variable "db_instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "RDS instance class (t4g.micro is the cheapest Graviton option)."
}

variable "db_allocated_storage" {
  type        = number
  default     = 20
  description = "RDS storage in GB."
}

variable "db_name" {
  type        = string
  default     = "app"
  description = "Initial database name."
}

variable "db_username" {
  type        = string
  default     = "app"
  description = "Master DB username."
}

variable "flow_log_traffic_type" {
  description = "Which VPC traffic the flow logs record: REJECT (cheapest; shows blocked and probing traffic), ACCEPT or ALL."
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["REJECT", "ACCEPT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be REJECT, ACCEPT or ALL."
  }
}

variable "db_protect" {
  description = "Production safeguards for RDS: deletion protection and a final snapshot. Off by default so a demo stack can be destroyed in one step."
  type        = bool
  default     = false
}

variable "db_multi_az" {
  description = "Run RDS with a standby in a second AZ, which takes over on its own if the primary or its AZ fails. Roughly doubles the RDS cost (instance and storage), so off for the demo stack."
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Put an AWS WAF web ACL in front of the ALB: AWS's managed rules for common attacks, bad inputs and bad-reputation IPs, plus a per-IP rate limit (waf.tf). Costs about $5 a month, plus $1 per rule and $0.60 per million requests."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Requests one IP may send in 5 minutes before WAF blocks it (with enable_waf)."
  type        = number
  default     = 1000

  validation {
    condition     = var.waf_rate_limit >= 10 && var.waf_rate_limit <= 2000000000
    error_message = "AWS WAF accepts a rate limit from 10 to 2,000,000,000 requests per 5 minutes."
  }
}

variable "requests_per_target" {
  description = "Opt-in request-count autoscaling: target ALB requests per task per minute. 0 (default) keeps CPU-only scaling; set >0 for an I/O-bound workload, so the service also scales to hold this many requests per task."
  type        = number
  default     = 0

  validation {
    condition     = var.requests_per_target >= 0
    error_message = "requests_per_target must be 0 (disabled) or a positive number of requests per task."
  }
}

variable "github_repository" {
  description = "owner/name of the GitHub repository whose deploy workflow may assume the deploy role."
  type        = string
  default     = "egezamb/prod-saas-aws"
}

variable "create_github_oidc_provider" {
  description = "Create the account's GitHub Actions OIDC provider. Set false if the account already has one (there can be only one per URL)."
  type        = bool
  default     = true
}
