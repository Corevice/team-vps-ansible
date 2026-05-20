# F14: IAM PutObject scope は per-host (SourceIdentity = 証明書 CN)
# vps-alice の credential では schema-v1/vps-alice/* にしか書き込めない

resource "aws_iam_role" "s3_log_writer" {
  name = "s3-log-writer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rolesanywhere.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:SetSourceIdentity", "sts:TagSession"]
      Condition = {
        StringEquals = {
          # SourceIdentity が 証明書 CN と一致することを強制
          "aws:PrincipalTag/x509Subject/CN" = "$${aws:SourceIdentity}"
        }
        ArnEquals = {
          "aws:SourceArn" = aws_rolesanywhere_trust_anchor.step_ca.arn
        }
      }
    }]
  })
}

data "aws_iam_policy_document" "s3_log_writer" {
  # F1 + F14: PutObject のみ、host 固有 prefix のみ
  statement {
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.logs.arn}/schema-v1/$${aws:SourceIdentity}/*"
    ]
  }

  # KMS encrypt 用
  statement {
    actions   = ["kms:GenerateDataKey"]
    resources = [aws_kms_key.logs.arn]
  }
}

resource "aws_iam_role_policy" "s3_log_writer" {
  name   = "s3-log-writer-inline"
  role   = aws_iam_role.s3_log_writer.id
  policy = data.aws_iam_policy_document.s3_log_writer.json
}
