# 11 × Cloudflare Tunnel (per-VPS)
# tunnel ID と credentials は Ansible Vault に手動転記 → cloudflared config に書き込み

resource "random_password" "tunnel_secret" {
  for_each = local.active_members
  length   = 64
  special  = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "vps" {
  for_each   = local.active_members
  account_id = local.common.cloudflare_account_id
  name       = "vps-${each.key}"
  config_src = "cloudflare"  # CF dashboard 側で config 管理

  tunnel_secret = base64encode(random_password.tunnel_secret[each.key].result)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "vps" {
  for_each   = local.active_members
  account_id = local.common.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.vps[each.key].id

  # WARP-to-Tunnel: v5 provider の config attr には warp_routing フィールドが無い。
  # CF マネージド config (config_src=cloudflare) では route 作成だけで WARP→Tunnel 接続が有効化される。
  # (参考: local config の cloudflared 使用時のみ config.yml の warp-routing.enabled が必要)
  config = {
    ingress = [
      {
        hostname = "vps-${each.key}.${local.common.domain}"
        service  = "http://127.0.0.1:8080"
        origin_request = {
          no_tls_verify   = true
          connect_timeout = 30
        }
      },
      {
        hostname = "ssh-${each.key}.${local.common.domain}"
        service  = "ssh://127.0.0.1:22"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

# Private Network route (warp_network_prefix.vps_id/32) → 該当 tunnel
# WARP クライアントからこの CIDR 宛てのトラフィックが Cloudflare edge 経由で
# 該当 VPS の cloudflared に届き、loopback の warp virtual IP に転送される
resource "cloudflare_zero_trust_tunnel_cloudflared_route" "vps" {
  for_each   = local.active_members
  account_id = local.common.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.vps[each.key].id
  network    = "${local.common.warp_network_prefix}.${each.value.vps_id}/32"
  comment    = "codens-vps-${each.key} (vps_id=${each.value.vps_id})"
}
