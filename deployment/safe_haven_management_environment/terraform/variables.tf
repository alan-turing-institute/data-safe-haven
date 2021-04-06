# # DNS
# variable "dns_rg_name" {
#   type = string
# }

# variable "dns_rg_location" {
#   type = string
# }

################################################
# Key Vault
################################################

variable "kv_rg_name" {
  type = string
}

variable "kv_rg_location" {
  type = string
}

variable "kv_name" {
  type = string
}

variable "kv_security_group_id" {
  type = string
}
