# Container Apps Environment
# The runtime platform for the mobile chat web app.
resource "azurerm_container_app_environment" "env" {
  name                       = "cae-${var.project_name}-${var.environment}"
  resource_group_name        = azurerm_resource_group.ai.name
  location                   = azurerm_resource_group.ai.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs.id
}

# Service Plan for Function App (Consumption = serverless, pay-per-execution)
resource "azurerm_service_plan" "func" {
  name                = "asp-${var.project_name}-${var.environment}-func"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan
}

# Azure Function App — nightly Workiz ticket sync
# Timer trigger: 3 AM daily (UTC). Polls Workiz, upserts into AI Search.
resource "azurerm_linux_function_app" "sync" {
  name                       = "func-${var.project_name}-${var.environment}-sync"
  resource_group_name        = azurerm_resource_group.ai.name
  location                   = azurerm_resource_group.ai.location
  service_plan_id            = azurerm_service_plan.func.id
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sync_func_identity.id]
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    WORKIZ_API_KEY                 = var.workiz_api_key
    SEARCH_ENDPOINT                = "https://${azurerm_search_service.search.name}.search.windows.net"
    SEARCH_INDEX_TICKETS           = "repair-tickets"
    OPENAI_ENDPOINT                = azurerm_cognitive_account.ai.endpoint
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
  }
}

# Outputs for deployment reference
output "container_apps_env_id" {
  description = "Container Apps Environment ID"
  value       = azurerm_container_app_environment.env.id
}

output "function_app_name" {
  description = "Function App name (nightly sync)"
  value       = azurerm_linux_function_app.sync.name
}

output "function_app_principal_id" {
  description = "Function App UAMI principal ID (for reference)"
  value       = azurerm_user_assigned_identity.sync_func_identity.principal_id
}
