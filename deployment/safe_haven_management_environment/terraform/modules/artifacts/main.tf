resource "azurerm_resource_group" "artifacts" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_storage_account" "artifacts" {
  name                     = var.sa_name
  resource_group_name      = azurerm_resource_group.artifacts.name
  location                 = azurerm_resource_group.artifacts.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}

resource "azurerm_storage_container" "artifacts_shm_dsc_dc" {
  name                  = "shm-dsc-dc"
  storage_account_name  = azurerm_storage_account.artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "CreateADPDC_zip" {
  name                   = "CreateADPDC.zip"
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_shm_dsc_dc.name
  type                   = "Block"
  source                 = var.dc_createadpdc_path
}

resource "azurerm_storage_blob" "CreateADBDC_zip" {
  name                   = "CreateADBDC.zip"
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_shm_dsc_dc.name
  type                   = "Block"
  source                 = var.dc_createadbdc_path
}

resource "azurerm_storage_container" "artifacts_shm_configuration_dc" {
  name                  = "shm-configuration-dc"
  storage_account_name  = azurerm_storage_account.artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "dc_config_files" {
  for_each = toset(var.dc_config_files)

  name                   = each.value
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_shm_configuration_dc.name
  type                   = "Block"
  source                 = format("%s/%s", var.dc_config_files_path, each.value)
}

resource "azurerm_storage_blob" "config_file_disconnect_ad" {
  name                   = "Disconnect_AD.ps1"
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_shm_configuration_dc.name
  type                   = "Block"
  source                 = var.dc_config_file_disconnect_ad
}

resource "azurerm_storage_container" "artifacts_sre_rds_sh_packages" {
  name                  = "sre-rds-sh-packages"
  storage_account_name  = azurerm_storage_account.artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "chrome" {
  name                   = "GoogleChrome_x64.msi"
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_sre_rds_sh_packages.name
  type                   = "Block"
  source_uri             = var.dc_chrome_source_uri
}

resource "azurerm_storage_blob" "putty" {
  name                   = "PuTTY_x64.msi"
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_sre_rds_sh_packages.name
  type                   = "Block"
  source_uri             = var.dc_putty_source_uri
}

resource "azurerm_storage_container" "artifacts_shm_configuration_nps" {
  name                  = "shm-configuration-nps"
  storage_account_name  = azurerm_storage_account.artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "nps_config_files" {
  for_each = toset(var.nps_config_files)

  name                   = each.value
  storage_account_name   = azurerm_storage_account.artifacts.name
  storage_container_name = azurerm_storage_container.artifacts_shm_configuration_nps.name
  type                   = "Block"
  source                 = format("%s/%s", var.nps_config_files_path, each.value)
}