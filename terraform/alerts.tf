# Where the alarms in observability.tf send their state changes. Subscribe an email with
# alarm_email, or attach Slack (AWS Chatbot), PagerDuty or a Lambda to alarm_topic_arn.

# The topic is encrypted with a key of its own, not the AWS managed aws/sns key: CloudWatch cannot
# use aws/sns, so an alarm publishing to a topic under it fails and nobody is told. A managed key's
# policy cannot be edited to let CloudWatch in; a customer managed key's can.
resource "aws_kms_key" "alarms" {
  description             = "${local.name} alarm notifications (SNS)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.alarms_key.json
  tags                    = { Name = "${local.name}-alarms" }
}

resource "aws_kms_alias" "alarms" {
  name          = "alias/${local.name}-alarms"
  target_key_id = aws_kms_key.alarms.key_id
}

data "aws_iam_policy_document" "alarms_key" {
  # The account keeps full control through IAM, as with a key's default policy; without this the key
  # could become unmanageable.
  statement {
    sid       = "AccountAdministers"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch needs a data key to publish an encrypted message, for this account's alarms only.
  statement {
    sid       = "CloudWatchAlarmsEncrypt"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic" "alarms" {
  name              = "${local.name}-alarms"
  kms_master_key_id = aws_kms_key.alarms.arn
  tags              = { Name = "${local.name}-alarms" }
}

# Only this account's CloudWatch alarms may publish (the confused-deputy guard AWS documents).
resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

data "aws_iam_policy_document" "alarms_topic" {
  statement {
    sid       = "CloudWatchAlarmsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# SNS mails a confirmation link first; nothing arrives until it is clicked.
resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
