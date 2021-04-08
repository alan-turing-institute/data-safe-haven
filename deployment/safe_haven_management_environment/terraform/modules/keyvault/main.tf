resource "azurerm_resource_group" "kv" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_key_vault" "kv" {
  name                        = var.name
  location                    = azurerm_resource_group.kv.location
  resource_group_name         = azurerm_resource_group.kv.name
  enabled_for_disk_encryption = true
  tenant_id                   = var.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.security_group_id

    key_permissions = [
      "Get", "List", "Update", "Create", "Import", "Delete",
      "Backup", "Restore", "Recover", "Purge",
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Recover", "Backup",
      "Restore", "Purge",
    ]

    certificate_permissions = [
      "Get", "List", "Delete", "Create", "Import", "Update", 
      "Managecontacts", "Getissuers", "Listissuers", "Setissuers",
      "Deleteissuers", "Manageissuers", "Recover", "Backup", "Restore", "Purge",
    ]

  }
}

resource "azurerm_key_vault_secret" "shm_aad_emergency_admin_username" {
  name         = var.secret_name_shm_aad_emergency_admin_username
  value        = var.secret_value_shm_aad_emergency_admin_username
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "shm_aad_emergency_admin_password" {
  name         = var.secret_name_shm_aad_emergency_admin_password
  value        = var.secret_value_shm_aad_emergency_admin_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "shm_domain_admin_username" {
  name         = var.secret_name_shm_domain_admin_username
  value        = var.secret_value_shm_domain_admin_username
  key_vault_id = azurerm_key_vault.kv.id
}


resource "azurerm_key_vault_secret" "shm_domain_admin_password" {
  name         = var.secret_name_shm_domain_admin_password
  value        = var.secret_value_shm_domain_admin_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "vm_safemode_password_dc" {
  name         = var.secret_name_shm_vm_safemode_password_dc
  value        = var.secret_value_shm_vm_safemode_password_dc
  key_vault_id = azurerm_key_vault.kv.id
}
