terraform {
  required_version = ">= 1.6.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # Phase 1: local backend (S3 tfstate bucket 未作成のため)
  # backend "s3" { bucket = "codens-tfstate-prod" ... } に Phase 2 で切替
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# F13: パス修正済 — terraform/cloudflare/ から見て members.yml は 2 段上
locals {
  members_data = yamldecode(file("${path.module}/../../members.yml"))
  members      = local.members_data.members
  common       = local.members_data.common
  active_members = {
    for slug, m in local.members : slug => m
    if m.lifecycle_state == "active"
  }
}

# F25 補強: IdP ID を data source で自動取得 (UI で UUID コピー不要)
# CF dashboard で先に One-time PIN と Google IdP を enable しておけば
# Terraform が type で識別して取得する
data "cloudflare_zero_trust_access_identity_providers" "all" {
  account_id = local.common.cloudflare_account_id
}

locals {
  google_idp = try(
    [for p in data.cloudflare_zero_trust_access_identity_providers.all.result :
     p if p.type == "google"][0],
    null
  )
  otp_idp = try(
    [for p in data.cloudflare_zero_trust_access_identity_providers.all.result :
     p if p.type == "onetimepin"][0],
    null
  )
  # Phase 1 は Corevice CF account に One-time PIN のみ登録。
  # operator (ops@corevice.com) も OTP で認証する (Google IdP は後で追加可)
  # allowed_idps は存在する IdP の ID だけを含める
  effective_google_idp_id = try(local.google_idp.id, "")
  effective_otp_idp_id    = try(local.otp_idp.id, "")
  allowed_idp_ids = compact([
    local.effective_google_idp_id,
    local.effective_otp_idp_id,
  ])
}
