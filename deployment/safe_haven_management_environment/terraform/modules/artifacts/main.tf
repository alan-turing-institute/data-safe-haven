resource "azurerm_resource_group" "artifacts" {
  name     = var.rg_name
  location = var.rg_location
}

resource "azurerm_storage_account" "bootdiagnostics" {
  name                     = var.boot_sa_name
  resource_group_name      = azurerm_resource_group.artifacts.name
  location                 = azurerm_resource_group.artifacts.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}

resource "azurerm_storage_account" "scripts" {
  name                     = var.script_sa_name
  resource_group_name      = azurerm_resource_group.artifacts.name
  location                 = azurerm_resource_group.artifacts.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}

data "azurerm_storage_account_sas" "dcscriptssas" {
    connection_string = azurerm_storage_account.scripts.primary_connection_string
    https_only        = true
    signed_version    = "2020-02-10"

    resource_types {
        container = true
        service   = true
        object    = true
    }

    services {
        blob  = true
        queue = false
        table = false
        file  = true
    }

    start  = timestamp()
    expiry = timeadd(timestamp(), "8h")

    permissions {
        read    = true
        write   = false
        delete  = false
        list    = true
        add     = false
        create  = false
        update  = false
        process = false
    }
}

output "dc_scripts_sas_token" {
    value = data.azurerm_storage_account_sas.dcscriptssas.sas
}

resource "azurerm_storage_container" "scripts_shm_configuration_dc" {
  name                  = "shm-configuration-dc"
  storage_account_name  = azurerm_storage_account.scripts.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "Active_Directory_Configuration_ps1" {
  name                   = "Active_Directory_Configuration.ps1"
  storage_account_name   = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.scripts_shm_configuration_dc.name
  type                   = "Block"
  source                 = var.dc_active_directory_configuration_path
}

resource "azurerm_storage_account" "artifacts" {
  name                     = var.art_sa_name
  resource_group_name      = azurerm_resource_group.artifacts.name
  location                 = azurerm_resource_group.artifacts.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
}

data "azurerm_storage_account_sas" "dcartifactssas" {
    connection_string = azurerm_storage_account.artifacts.primary_connection_string
    https_only        = true
    signed_version    = "2020-02-10"

    resource_types {
        container = true
        service   = true
        object    = true
    }

    services {
        blob  = true
        queue = false
        table = false
        file  = true
    }

    start  = timestamp()
    expiry = timeadd(timestamp(), "8h")

    permissions {
        read    = true
        write   = false
        delete  = false
        list    = true
        add     = false
        create  = false
        update  = false
        process = false
    }
}

output "dc_artifact_sas_token" {
    value = data.azurerm_storage_account_sas.dcartifactssas.sas
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