# Base resource group for all appliance-ai infrastructure
resource "azurerm_resource_group" "ai" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
}
