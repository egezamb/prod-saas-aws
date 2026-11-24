# Optional ALB access logs (enable_alb_access_logs): one line per request (client IP, path, status,
# target latency, TLS cipher), written to S3 every 5 minutes. Off by default; AWS charges nothing
# for delivery, only S3 storage. They expire after 30 days, like the CloudWatch log groups.

# trivy:ignore:AWS-0089 This bucket only receives logs; logging access to a log bucket would need yet another bucket.
# trivy:ignore:AWS-0090 Versioning would keep every expired log as a noncurrent version and defeat the lifecycle rule.
resource "aws_s3_bucket" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  # S3 names are global; the account ID keeps this one from clashing with another account's stack.
  bucket = "${local.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  # With db_protect (real production) the logs stay when the stack is destroyed; without it, a demo
  # stack still goes in one step.
  force_destroy = !var.db_protect

  tags = { Name = "${local.name}-alb-logs" }
}

# trivy:ignore:AWS-0132 ALB access logs support SSE-S3 only; ELB cannot deliver to a bucket that uses SSE-KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# The service principal AWS documents for every region; the older per-region ELB account policy is
# only kept for regions from before August 2022. Writes are limited to this account's prefix, and
# any request without TLS is denied.
data "aws_iam_policy_document" "alb_logs" {
  count = var.enable_alb_access_logs ? 1 : 0

  statement {
    sid       = "ELBLogDeliveryWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs[0].arn, "${aws_s3_bucket.alb_logs[0].arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  policy = data.aws_iam_policy_document.alb_logs[0].json

  # The public access block must exist first, or a policy could briefly be evaluated without it.
  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}
