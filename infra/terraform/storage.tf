# Storage Account for the Azure Function App
# Used for function state, triggers, and timer-based storage.
resource "azurerm_storage_account" "func" {
  name                     = "${local.project_name_sanitized}${var.environment}fn"
  resource_group_name      = azurerm_resource_group.ai.name
  location                 = azurerm_resource_group.ai.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Outputs for reference
output "storage_account_name" {
  description = "Storage account name (for function app state)"
  value       = azurerm_storage_account.func.name
}
