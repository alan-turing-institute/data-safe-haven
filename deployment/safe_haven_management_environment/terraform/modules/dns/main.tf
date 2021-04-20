resource "azurerm_resource_group" "dns" {
  name     = var.rg_name
  location = var.rg_location
}