terraform {
  required_version = ">= 1.6.0"
  required_providers {
    contabo = {
      source  = "contabo/contabo"
      version = "~> 0.1"
    }
  }
}

provider "contabo" {
  oauth2_client_id     = var.client_id
  oauth2_client_secret = var.client_secret
  oauth2_user          = var.user
  oauth2_pass          = var.password
}

locals {
  members_data   = yamldecode(file("${path.module}/../../../members.yml"))
  active_members = {
    for slug, m in local.members_data.members : slug => m
    if m.lifecycle_state == "active" && m.contabo_account == "portament"
  }
  operator = local.members_data.operator
}
