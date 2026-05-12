# Log Analytics Workspace
# Central logging and monitoring for Container Apps, Function App, and other services.
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Outputs for reference
output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.logs.id
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace name"
  value       = azurerm_log_analytics_workspace.logs.name
}

# KQL query string for debugging indexer errors (use in Azure Portal > Logs)
output "kql_indexer_errors_query" {
  description = "KQL query to find Search Service indexer errors in Log Analytics"
  value       = "AzureDiagnostics | where ResourceType == \"SEARCHSERVICES\" | where Category == \"ExecSummary\" or Category == \"OperationLogs\" | where Status =~ \"Error\" or Status =~ \"Failed\" or ErrorDetail != \"\" | project TimeGenerated, OperationName, Status, ErrorDetail, Details | sort by TimeGenerated desc"
}
