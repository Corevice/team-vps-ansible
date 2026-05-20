# 42 × Access Application (21 member × (code-server + SSH))
# v5 schema: policies は application 内に inline 定義 (precedence + decision + include)

resource "cloudflare_zero_trust_access_application" "code_server" {
  for_each         = local.active_members
  account_id       = local.common.cloudflare_account_id
  name             = "code-server-${each.key}"
  domain           = "vps-${each.key}.${local.common.domain}"
  type             = "self_hosted"
  session_duration = "24h"

  allowed_idps              = local.allowed_idp_ids
  auto_redirect_to_identity = false

  policies = [
    {
      precedence = 1
      decision   = "allow"
      name       = "owner-${each.key}"
      include = [{
        email = { email = each.value.owner_email }
      }]
    },
    {
      precedence = 2
      decision   = "allow"
      name       = "operator-override"
      include = [{
        email = { email = local.members_data.operator.email }
      }]
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "ssh" {
  for_each         = local.active_members
  account_id       = local.common.cloudflare_account_id
  name             = "ssh-${each.key}"
  domain           = "ssh-${each.key}.${local.common.domain}"
  type             = "self_hosted"
  session_duration = "24h"

  allowed_idps              = local.allowed_idp_ids
  auto_redirect_to_identity = false

  policies = [
    {
      precedence = 1
      decision   = "allow"
      name       = "owner-${each.key}"
      include = [{
        email = { email = each.value.owner_email }
      }]
    },
    {
      precedence = 2
      decision   = "allow"
      name       = "operator-override"
      include = [{
        email = { email = local.members_data.operator.email }
      }]
    },
  ]
}
