output "s3_logs_bucket" {
  value = aws_s3_bucket.logs.bucket
}

output "s3_logs_kms_key_arn" {
  value = aws_kms_key.logs.arn
}

output "roles_anywhere_trust_anchor_arn" {
  value = aws_rolesanywhere_trust_anchor.step_ca.arn
}

output "roles_anywhere_profile_arn" {
  value = aws_rolesanywhere_profile.s3_log_writer.arn
}

output "s3_log_writer_role_arn" {
  value = aws_iam_role.s3_log_writer.arn
}

# SES outputs (sensitive — Vault に転記する用)
output "ses_smtp_username" {
  value     = aws_iam_access_key.ses_smtp.id
  sensitive = true
}

output "ses_smtp_password" {
  value     = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
  sensitive = true
}

# DKIM / MAIL FROM の DNS records
# 出力された値を corevice.com の DNS 管理元 (Cloudflare 等) に手動追加
output "ses_dns_records_to_add" {
  value = {
    dkim_cnames = [
      for token in aws_ses_domain_dkim.corevice.dkim_tokens : {
        name  = "${token}._domainkey.${var.domain}"
        type  = "CNAME"
        value = "${token}.dkim.amazonses.com"
      }
    ]
    mail_from_mx = {
      name     = "alerts.${var.domain}"
      type     = "MX"
      value    = "feedback-smtp.${var.aws_region}.amazonses.com"
      priority = 10
    }
    mail_from_spf = {
      name  = "alerts.${var.domain}"
      type  = "TXT"
      value = "v=spf1 include:amazonses.com -all"
    }
    domain_dmarc_recommended = {
      name  = "_dmarc.${var.domain}"
      type  = "TXT"
      value = "v=DMARC1; p=quarantine; rua=mailto:dmarc@${var.domain}"
    }
  }
}

output "ses_setup_instructions" {
  value = <<-EOT
    1. 上記 ses_dns_records_to_add を corevice.com の DNS 管理元に追加
    2. SES console で domain verification status が "Verified" になるまで待つ (~30 min)
    3. ses_smtp_username / ses_smtp_password を 1Password と Ansible Vault に保存:
       terraform output -raw ses_smtp_username
       terraform output -raw ses_smtp_password
    4. swaks で smoke test (plan §4.7-bis 末尾参照)
    5. ops@corevice.com に AWS から確認メール → リンク click で sandbox verified
  EOT
}
