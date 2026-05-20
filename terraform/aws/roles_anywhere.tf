# F6: trust anchor は step-ca の root CA を使う
# F14: profile に attribute_mappings を設定し、証明書 CN → SourceIdentity を自動 set

variable "step_ca_root_cert_path" {
  description = "step-ca で生成した root CA 証明書 (PEM) のローカルファイルパス"
  type        = string
  default     = "../../scripts/step-ca-root.crt"
}

resource "aws_rolesanywhere_trust_anchor" "step_ca" {
  name    = "codens-vps-step-ca"
  enabled = true

  source {
    source_type = "CERTIFICATE_BUNDLE"
    source_data {
      x509_certificate_data = file(var.step_ca_root_cert_path)
    }
  }
}

resource "aws_rolesanywhere_profile" "s3_log_writer" {
  name      = "vps-s3-log-writer"
  role_arns = [aws_iam_role.s3_log_writer.arn]
  enabled   = true

  # F14: 証明書 CN を SourceIdentity に変換
  # これにより IAM policy の ${aws:SourceIdentity} = vps-alice 等が成立
  attribute_mappings {
    certificate_field = "x509Subject"
    mapping_rules {
      specifier = "CN"
    }
    source = "SET_SOURCE_IDENTITY"
  }

  require_instance_properties = true
}
