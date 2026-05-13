# Storage Account for the Azure Function App
# Used for function state, triggers, and timer-based storage.
resource "azurerm_storage_account" "func" {
  name                     = "stor${local.project_name_sanitized}${var.environment}func01"
  resource_group_name      = azurerm_resource_group.ai.name
  location                 = azurerm_resource_group.ai.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Blob container for service manual PDFs (uploaded by technicians / admin)
# Naming convention: {brand}/{model-series}/filename.pdf (or flat filename.pdf)
resource "azurerm_storage_container" "service_manuals" {
  name                  = "service-manuals"
  storage_account_id    = azurerm_storage_account.func.id
  container_access_type = "private"
}

# -------------------------------------------------------
# Storage Account for AI Knowledge Base
# -------------------------------------------------------
# Dedicated storage for service manual PDFs and AI enriched knowledge.
# Uses Azure AD RBAC (no storage keys) for secure access via managed identities.
resource "azurerm_storage_account" "knowledge" {
  name                              = "stor${local.project_name_sanitized}${var.environment}know01"
  resource_group_name               = azurerm_resource_group.ai.name
  location                          = azurerm_resource_group.ai.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  shared_access_key_enabled         = false
  infrastructure_encryption_enabled = true
}

# Blob container for service manual PDFs
resource "azurerm_storage_container" "knowledge_service_manuals" {
  name                  = "service-manuals"
  storage_account_id    = azurerm_storage_account.knowledge.id
  container_access_type = "private"
}

# Diagnostic settings for the knowledge blob service logs and metrics
resource "azurerm_monitor_diagnostic_setting" "knowledge_storage_diagnostics" {
  name                       = "knowledge-storage-diagnostics"
  target_resource_id         = "${azurerm_storage_account.knowledge.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Capacity"
  }

  enabled_metric {
    category = "Transaction"
  }
}

# Outputs for reference
output "storage_account_name" {
  description = "Storage account name (for function app state and document storage)"
  value       = azurerm_storage_account.func.name
}

output "service_manuals_container_name" {
  description = "Blob container name for service manual PDFs"
  value       = azurerm_storage_container.service_manuals.name
}

output "knowledge_storage_account_name" {
  description = "Knowledge base storage account name"
  value       = azurerm_storage_account.knowledge.name
}

output "knowledge_storage_account_id" {
  description = "Knowledge base storage account ID"
  value       = azurerm_storage_account.knowledge.id
}

output "knowledge_service_manuals_container_name" {
  description = "Knowledge base service manuals container name"
  value       = azurerm_storage_container.knowledge_service_manuals.name
}
