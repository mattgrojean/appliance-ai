# Entra ID (Azure AD) Identity Resources
# Protects the chat web app with organization-level authentication.
# Uses User-Assigned Managed Identities (UAMI) for explicit, upfront role assignment.

data "azuread_client_config" "current" {}

# -------------------------------------------------------
# User-Assigned Managed Identities
# -------------------------------------------------------

# UAMI for the Chat Web App (Container App)
# Permissions: Read from Azure AI Search, call Azure OpenAI
resource "azurerm_user_assigned_identity" "chat_app_identity" {
  name                = "uami-${var.project_name}-${var.environment}-chat"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
}

# UAMI for the Workiz Sync Function App
# Permissions: Write to Azure AI Search (upsert indexes)
resource "azurerm_user_assigned_identity" "sync_func_identity" {
  name                = "uami-${var.project_name}-${var.environment}-sync"
  resource_group_name = azurerm_resource_group.ai.name
  location            = azurerm_resource_group.ai.location
}

# -------------------------------------------------------
# Entra ID App Registration for Chat Web App
# -------------------------------------------------------
# Users will sign in with their org account to use the technician chat.
resource "azuread_application" "chat_app" {
  display_name = "Appliance AI Chat (${var.environment})"

  web {
    # Redirect URI will be updated after the Container App gets its URL.
    # Placeholder allows the app registration to be created now.
    # Phase 6 will update this with the actual Container App URL.
    redirect_uris = ["https://ca-${var.project_name}-${var.environment}.placeholder.azurecontainerapps.io/auth/callback"]
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }
}

# Service Principal for the Entra app
resource "azuread_service_principal" "chat_app" {
  client_id = azuread_application.chat_app.client_id
}

# -------------------------------------------------------
# Outputs
# -------------------------------------------------------
output "chat_app_identity_id" {
  description = "Chat App User-Assigned Managed Identity ID"
  value       = azurerm_user_assigned_identity.chat_app_identity.id
}

output "chat_app_identity_principal_id" {
  description = "Chat App UAMI principal ID (for RBAC)"
  value       = azurerm_user_assigned_identity.chat_app_identity.principal_id
}

output "sync_func_identity_id" {
  description = "Sync Function User-Assigned Managed Identity ID"
  value       = azurerm_user_assigned_identity.sync_func_identity.id
}

output "sync_func_identity_principal_id" {
  description = "Sync Function UAMI principal ID (for RBAC)"
  value       = azurerm_user_assigned_identity.sync_func_identity.principal_id
}

output "entra_client_id" {
  description = "Entra ID application (client) ID for the chat app"
  value       = azuread_application.chat_app.client_id
}

output "entra_tenant_id" {
  description = "Entra ID tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "entra_app_object_id" {
  description = "Entra ID app object ID"
  value       = azuread_application.chat_app.object_id
}

