# Tunnel CNAME records (vps-*.domain と ssh-*.domain を tunnel に向ける)

data "cloudflare_zone" "vps_zone" {
  filter = {
    name = local.common.domain
  }
}

resource "cloudflare_dns_record" "code_server" {
  for_each = local.active_members
  zone_id  = data.cloudflare_zone.vps_zone.id
  name     = "vps-${each.key}"
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.vps[each.key].id}.cfargotunnel.com"
  ttl      = 1  # auto when proxied
  proxied  = true
}

resource "cloudflare_dns_record" "ssh" {
  for_each = local.active_members
  zone_id  = data.cloudflare_zone.vps_zone.id
  name     = "ssh-${each.key}"
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.vps[each.key].id}.cfargotunnel.com"
  ttl      = 1
  proxied  = true
}
