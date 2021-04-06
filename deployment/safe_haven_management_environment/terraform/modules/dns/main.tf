resource "azurerm_resource_group" "example" {
  name     = var.rg_name
  location = var.rg_location
}