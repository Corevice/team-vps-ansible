variable "client_id" {
  type      = string
  sensitive = true
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "user" {
  type      = string
  sensitive = true
}

variable "password" {
  type      = string
  sensitive = true
}

variable "enable_bootstrap_ssh" {
  type    = bool
  default = true
}
