# F1: S3 bucket with Object Lock (Governance, 90 days bucket default retention)
# F4: lifecycle で古いオブジェクトを削除
# F7: prefix は schema-v1/ で開始 (将来 schema-v2 と並行可能)
# F14: per-host scope は IAM 側で SourceIdentity 制御

resource "aws_s3_bucket" "logs" {
  bucket              = "codens-vps-logs-prod"
  force_destroy       = false
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.log_retention_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {
      prefix = "schema-v1/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.lifecycle_expire_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_expire_days
    }
  }
}
