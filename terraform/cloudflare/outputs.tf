output "tunnel_credentials" {
  description = "Per-VPS tunnel credentials (Vault に転記、cloudflared config に書き込む)"
  sensitive   = true
  value = {
    for slug, member in local.active_members : slug => {
      tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.vps[slug].id
      account_tag = local.common.cloudflare_account_id
      tunnel_secret = random_password.tunnel_secret[slug].result
      # cloudflared が読む credentials.json 形式
      credentials_json = jsonencode({
        AccountTag   = local.common.cloudflare_account_id
        TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.vps[slug].id
        TunnelSecret = base64encode(random_password.tunnel_secret[slug].result)
      })
    }
  }
}

output "code_server_urls" {
  value = {
    for slug, m in local.active_members : slug =>
    "https://vps-${slug}.${local.common.domain}"
  }
}

output "ssh_hostnames" {
  value = {
    for slug, m in local.active_members : slug =>
    "ssh-${slug}.${local.common.domain}"
  }
}
