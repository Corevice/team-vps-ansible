# Qwen GW Tunnel — private network only (no public hostname)
#
# Goal: VPSs reach the Qwen GW pod via Cloudflare Zero Trust private network
# (10.200.0.99) instead of the public `proxy.runpod.net` endpoint, which has
# a hard 120s TTFT timeout that produces 524 cascades on heavy requests.
#
# Pattern mirrors per-VPS tunnels in tunnels.tf: managed config via CF
# dashboard (config_src = "cloudflare"), route 10.200.0.99/32 → tunnel.
# WARP-to-Tunnel routing is implicit when route is created (per existing
# comment in tunnels.tf line 19-22 — v5 provider config attr lacks the
# warp_routing field, but route creation alone enables WARP→Tunnel reach).

resource "random_password" "qwen_gw_tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "qwen_gw" {
  account_id    = local.common.cloudflare_account_id
  name          = "qwen-gw"
  config_src    = "cloudflare"
  tunnel_secret = base64encode(random_password.qwen_gw_tunnel_secret.result)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "qwen_gw" {
  account_id = local.common.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.qwen_gw.id

  # HTTP ingress: VPSs reach pod at https://qwen-gw.vps.example.com.
  # WARP private network routing was attempted first (10.200.0.99/32) but
  # RunPod pod containers lack NET_ADMIN so we cannot bind that VIP on lo.
  # Hostname-based ingress works without IP binding — request hits CF edge,
  # tunnel forwards to pod's cloudflared, cloudflared proxies to localhost:4000.
  #
  # 2026-05-19: added qwen-gw-1/2/3 entries. AWS LB (qwen-llmgw/aws-lb) does
  # nginx-level fan-out to per-pod hostnames (qwen-gw-N.vps.example.com) for
  # multi-pod failover. Each per-pod DNS CNAME points to THIS same tunnel
  # because in practice every pod's cloudflared connects to it (single
  # tunnel, N pod connectors load-balanced by CF edge). Without these
  # ingress entries CF returns 404 for the per-pod hostnames — exactly
  # what produced the 17:00 outage when LB sent traffic to qwen-gw-1 and
  # the tunnel didn't have a matching ingress rule.
  config = {
    ingress = [
      {
        hostname = "qwen-gw.${local.common.domain}"
        service  = "http://localhost:4000"
        origin_request = {
          no_tls_verify   = true
          connect_timeout = 30
        }
      },
      {
        hostname = "qwen-gw-1.${local.common.domain}"
        service  = "http://localhost:4000"
        origin_request = {
          no_tls_verify   = true
          connect_timeout = 30
        }
      },
      {
        hostname = "qwen-gw-2.${local.common.domain}"
        service  = "http://localhost:4000"
        origin_request = {
          no_tls_verify   = true
          connect_timeout = 30
        }
      },
      {
        hostname = "qwen-gw-3.${local.common.domain}"
        service  = "http://localhost:4000"
        origin_request = {
          no_tls_verify   = true
          connect_timeout = 30
        }
      },
      { service = "http_status:404" },
    ]
  }
}

# DNS record for qwen-gw.vps.example.com is managed by aws-lb/cloudflare.tf
# (resource cloudflare_record.qwen_lb) — it points to the qwen-lb tunnel
# (5828f354-...) running on the AWS LB EC2, NOT directly to this qwen-gw
# tunnel. The LB EC2's nginx then fans out to qwen-gw-1/2/3.vps.example.com
# (which DO map to this tunnel) for per-pod retry chain.
#
# Pre-2026-05-19 this file had its own cloudflare_dns_record.qwen_gw that
# would have overwritten content with this tunnel id, bypassing the LB
# entirely — that's exactly the kind of accidental regression we caught
# at 17:00. Resource removed; ownership moved to aws-lb/ for clarity.
#
# Per-pod hostnames (qwen-gw-1/2/3.vps.example.com) are also defined as
# separate DNS records (manually created on CF, not yet terraform-managed
# anywhere — TODO follow-up: add cloudflare_dns_record.qwen_gw_pods to
# aws-lb/ for the per-pod CNAMEs).

# Connector token for `cloudflared tunnel run --token <T>`.
# IMPORTANT: short-key format ({a, t, s}) — not {AccountTag, TunnelID,
# TunnelSecret} which is the credentials-FILE format. Wrong format causes
# cloudflared to error "Failed to get tunnel" (observed 2026-05-01 first
# attempt). The format below matches what `GET /accounts/.../cfd_tunnel/.../token`
# returns from CF API.
output "qwen_gw_tunnel_token" {
  value = base64encode(jsonencode({
    a = local.common.cloudflare_account_id
    t = cloudflare_zero_trust_tunnel_cloudflared.qwen_gw.id
    s = base64encode(random_password.qwen_gw_tunnel_secret.result)
  }))
  sensitive = true
}
