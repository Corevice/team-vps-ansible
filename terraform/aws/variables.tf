variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = "purple-codens-prod"
}

variable "domain" {
  description = "corevice.com (SES domain identity 用、A-6 で買った VPS ドメインではなく組織のドメイン)"
  type        = string
  default     = "corevice.com"
}

variable "alert_recipient" {
  description = "SES sandbox 期間中の verified 送信先"
  type        = string
  default     = "ops@example.com"
}

variable "members" {
  description = "members.yml から渡されるメンバー一覧 (host_id 配列)。Roles Anywhere certificate 発行用"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Object Lock の default retention period (日)"
  type        = number
  default     = 90
}

variable "lifecycle_expire_days" {
  description = "S3 lifecycle で古いオブジェクトを削除する日数"
  type        = number
  default     = 365
}
