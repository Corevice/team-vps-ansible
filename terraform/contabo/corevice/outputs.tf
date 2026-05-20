output "firewall_id" {
  value = contabo_firewall.fw.id
}

output "instance_ids" {
  value = [for s, m in local.active_members : m.contabo_instance_id]
}
