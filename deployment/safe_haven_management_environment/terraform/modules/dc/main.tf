resource "azurerm_resource_group" "dc" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_resource_group" "dc_bootdiagnostics" {
  name     = var.rg_name_bootdiagnostics
  location = var.rg_location
}

resource "azurerm_storage_account" "dc_bootdiagnostics" {
  name                     = var.sa_name_bootdiagnostics
  resource_group_name      = azurerm_resource_group.dc_bootdiagnostics.name
  location                 = azurerm_resource_group.dc_bootdiagnostics.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}

resource "azurerm_resource_group" "dc_artifacts" {
  name     = var.rg_name_artifacts
  location = var.rg_location
}

resource "azurerm_storage_account" "dc_artifacts" {
  name                     = var.sa_name_artifacts
  resource_group_name      = azurerm_resource_group.dc_artifacts.name
  location                 = azurerm_resource_group.dc_artifacts.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}

resource "azurerm_storage_container" "dc_artifacts_shm-dsc-dc" {
  name                  = "shm-dsc-dc"
  storage_account_name  = azurerm_storage_account.dc_artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "dc_artifacts_shm-configuration-dc" {
  name                  = "shm-configuration-dc"
  storage_account_name  = azurerm_storage_account.dc_artifacts.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "dc_artifacts_sre-rds-sh-packages" {
  name                  = "sre-rds-sh-packages"
  storage_account_name  = azurerm_storage_account.dc_artifacts.name
  container_access_type = "private"
}