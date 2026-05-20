resource "contabo_firewall" "fw" {
  name        = "codens-vps-fw-portament"
  description = "Codens Team VPS — portament account"
  status      = "active"

  instance_ids = toset([
    for slug, m in local.active_members : tonumber(m.contabo_instance_id)
  ])

  dynamic "rules" {
    for_each = var.enable_bootstrap_ssh ? [1] : []
    content {
      inbound {
        action     = "accept"
        protocol   = "tcp"
        dest_ports = ["22"]
        status     = "active"
        src_cidr {
          ipv4 = ["${local.operator.management_ip}/32"]
        }
      }
    }
  }
}
