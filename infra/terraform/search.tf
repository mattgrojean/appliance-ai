# Azure AI Search — the knowledge index for technician chat and SEO pipeline
# Supports hybrid search (full-text + semantic).
resource "azurerm_search_service" "search" {
  name                = "srch-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
  sku                 = "free"

  # "free" tier: no cost, 50MB storage, 3 indexes, no semantic search.
  # Upgrade to "standard" when you need semantic ranking and higher capacity.
  # Change to: sku = "standard" and set semantic_search_sku = "standard" below.
  # semantic_search_sku = "standard"
}

# Outputs for SDK/app configuration
output "search_endpoint" {
  description = "Azure AI Search endpoint URL"
  value       = "https://${azurerm_search_service.search.name}.search.windows.net"
}

output "search_service_name" {
  description = "Azure AI Search service name"
  value       = azurerm_search_service.search.name
}
