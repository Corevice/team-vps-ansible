variable "cloudflare_api_token" {
  description = "CF API token (Tunnel:Edit + Access:Edit + DNS:Edit + Zone:Read)"
  type        = string
  sensitive   = true
}

variable "google_idp_id" {
  description = "Optional: Google IdP ID (data source 取得不能時の fallback)。通常は空欄で OK"
  type        = string
  default     = ""
}

variable "otp_idp_id" {
  description = "Optional: One-time PIN IdP ID (data source 取得不能時の fallback)。通常は空欄で OK"
  type        = string
  default     = ""
}
