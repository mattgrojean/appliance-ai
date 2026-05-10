# Azure Container App — Technician Chat Web App
# Runs the mobile-friendly chat UI + FastAPI backend.
# This resource will be deployed in Phase 6 after the Docker image is built and pushed to ACR.

# NOTE: This resource is currently commented out because the Docker image doesn't exist yet.
# Uncomment this after:
# 1. Build the chat app (ai/app/)
# 2. Push the image to ACR (acrtechaimsdndev.azurecr.io)
#
# Then run: terraform plan -var-file="environments/dev/dev.tfvars"
#          terraform apply -var-file="environments/dev/dev.tfvars"

/*
resource "azurerm_container_app" "chat" {
  name                         = "ca-${var.project_name}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.ai.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.chat_app_identity.id]
  }

  template {
    container {
      name   = "chat-app"
      image  = "${azurerm_container_registry.acr.login_server}/appliance-ai-chat:latest"
      cpu    = "0.5"
      memory = "1Gi"

      env {
        name  = "OPENAI_ENDPOINT"
        value = azurerm_cognitive_account.ai.endpoint
      }
      env {
        name  = "SEARCH_ENDPOINT"
        value = "https://${azurerm_search_service.search.name}.search.windows.net"
      }
      env {
        name  = "SEARCH_INDEX_TICKETS"
        value = "repair-tickets"
      }
      env {
        name  = "SEARCH_INDEX_MANUALS"
        value = "service-manuals"
      }
      env {
        name  = "ENTRA_CLIENT_ID"
        value = azuread_application.chat_app.client_id
      }
      env {
        name  = "ENTRA_TENANT_ID"
        value = data.azuread_client_config.current.tenant_id
      }
    }
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8000
    traffic_weight {
      latest_revision = true
      percent         = 100
    }
  }
}

# Update the Entra app registration redirect URI with the actual Container App URL
resource "azuread_application_redirect_uris" "chat_app_redirect" {
  application_id = azuread_application.chat_app.id
  redirect_uris = [
    "https://${azurerm_container_app.chat.ingress[0].fqdn}/auth/callback"
  ]
}

output "chat_app_url" {
  description = "Chat App public URL"
  value       = "https://${azurerm_container_app.chat.ingress[0].fqdn}"
}
*/
