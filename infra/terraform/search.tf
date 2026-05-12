# Azure AI Search — the knowledge index for technician chat and SEO pipeline
# Supports hybrid search (full-text + semantic).
# Deployed to search_location (may differ from primary region if primary is out of capacity).
resource "azurerm_search_service" "search" {
  name                = "srch-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.ai.name
  location            = var.search_location
  sku                 = "standard"
  semantic_search_sku = "standard"

  # Enable RBAC authentication (aadOrApiKey) so managed identities and
  # az-login credentials can call the Search API without an API key.
  # This is required for DefaultAzureCredential / AzureCliCredential to work.
  authentication_failure_mode = "http401WithBearerChallenge"

  # "free" tier: no cost, 50MB storage, 3 indexes, no semantic search.
  # Upgrade to "standard" when you need semantic ranking and higher capacity.
  # Change to: sku = "standard" and set semantic_search_sku = "standard" below.
  # semantic_search_sku = "standard"
}

# Diagnostic settings for Azure AI Search indexer logs and metrics
resource "azurerm_monitor_diagnostic_setting" "search_diagnostics" {
  name                           = "search-diagnostics"
  target_resource_id             = azurerm_search_service.search.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.logs.id
  log_analytics_destination_type = "Dedicated"

  # Enable operation logs to capture indexer execution, queries, and errors
  enabled_log {
    category = "OperationLogs"
  }

  # Enable metrics for service health monitoring
  enabled_metric {
    category = "AllMetrics"
  }
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
