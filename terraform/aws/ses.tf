# F23: AWS SES SMTP relay
# 既存の Google Workspace app password アプローチ廃止
# corevice.com は外部 (場合により別 registrar) で管理されている前提
#   → DKIM/MAIL FROM の DNS records は手動追加 (terraform output に手順表示)

resource "aws_ses_domain_identity" "corevice" {
  domain = var.domain
}

resource "aws_ses_domain_dkim" "corevice" {
  domain = aws_ses_domain_identity.corevice.domain
}

resource "aws_ses_domain_mail_from" "corevice" {
  domain           = aws_ses_domain_identity.corevice.domain
  mail_from_domain = "alerts.${var.domain}"
}

# Sandbox 期間中の verified 送信先
resource "aws_ses_email_identity" "alert_recipient" {
  email = var.alert_recipient
}

# SMTP credential 用 IAM user
resource "aws_iam_user" "ses_smtp" {
  name = "ses-smtp-codens-vps-alerts"
  tags = {
    Purpose = "SES SMTP relay for monit alerts"
  }
}

data "aws_iam_policy_document" "ses_send" {
  statement {
    actions   = ["ses:SendRawEmail", "ses:SendEmail"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = ["alerts@${var.domain}"]
    }
  }
}

resource "aws_iam_user_policy" "ses_smtp" {
  name   = "ses-send-only"
  user   = aws_iam_user.ses_smtp.name
  policy = data.aws_iam_policy_document.ses_send.json
}

resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}

# CloudWatch alarm: bounce rate > 5%
resource "aws_cloudwatch_metric_alarm" "ses_bounce_rate" {
  alarm_name          = "codens-vps-ses-bounce-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Reputation.BounceRate"
  namespace           = "AWS/SES"
  period              = 3600
  statistic           = "Average"
  threshold           = 0.05
  alarm_description   = "SES bounce rate exceeded 5% — risk of sending pause"
  treat_missing_data  = "notBreaching"
  # alarm_actions は SNS topic 作成後に設定
}

resource "aws_cloudwatch_metric_alarm" "ses_complaint_rate" {
  alarm_name          = "codens-vps-ses-complaint-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Reputation.ComplaintRate"
  namespace           = "AWS/SES"
  period              = 3600
  statistic           = "Average"
  threshold           = 0.001
  alarm_description   = "SES complaint rate exceeded 0.1% — risk of sending pause"
  treat_missing_data  = "notBreaching"
}
