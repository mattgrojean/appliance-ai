# Azure Container Registry
# Stores Docker images for the chat web app and other containerized services.
resource "azurerm_container_registry" "acr" {
  name                = "acr${local.project_name_sanitized}${var.environment}"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
  sku                 = "Basic"
  admin_enabled       = false
}

# Outputs for deployment scripts
output "acr_login_server" {
  description = "Container Registry login server URL"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_resource_id" {
  description = "Container Registry resource ID"
  value       = azurerm_container_registry.acr.id
}
