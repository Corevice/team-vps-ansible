resource "aws_kms_key" "logs" {
  description             = "KMS CMK for codens-vps log bucket (SSE-KMS)"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowS3LogWriterUseOfKey"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.s3_log_writer.arn }
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "logs" {
  name          = "alias/codens-vps-logs-key"
  target_key_id = aws_kms_key.logs.key_id
}

data "aws_caller_identity" "current" {}
