# Azure Container App — Technician Chat Web App
# Runs the mobile-friendly chat UI + FastAPI backend.
# This resource will be deployed after the Docker image is built and pushed to ACR.

# NOTE: This block is commented out until the Docker image exists at:
#   acrtechaimsdndev.azurecr.io/appliance-ai-chat:latest
#
# Build the image first:
#   az acr build --registry acrtechaimsdndev --image appliance-ai-chat:latest ai/app
#
# Then uncomment this block and run:
#   terraform apply -var-file="environments/dev/dev.tfvars"
#
# After apply, enable Easy Auth (one-time):
#   az containerapp auth microsoft update \
#     --name ca-techai-msdn-dev \
#     --resource-group rg-techai-msdn-dev \
#     --client-id <ENTRA_APP_CLIENT_ID> \
#     --client-secret "<ENTRA_APP_CLIENT_SECRET>" \
#     --issuer https://login.microsoftonline.com/<TENANT_ID>/v2.0

resource "azurerm_container_app" "chat" {
  name                         = "ca-${var.project_name}-${var.environment}"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.ai.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.chat_app_identity.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.chat_app_identity.id
  }

  template {
    min_replicas = 0
    max_replicas = 3

    container {
      name   = "chat-app"
      image  = "${azurerm_container_registry.acr.login_server}/appliance-ai-chat:latest"
      cpu    = "0.5"
      memory = "1Gi"

      # UAMI client_id — used by ManagedIdentityCredential at runtime
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.chat_app_identity.client_id
      }

      # AI Inference endpoint for azure-ai-inference ChatCompletionsClient
      env {
        name  = "AZURE_INFERENCE_ENDPOINT"
        value = "https://${azurerm_cognitive_account.ai.custom_subdomain_name}.services.ai.azure.com/models"
      }

      env {
        name  = "AZURE_AI_CHAT_DEPLOYMENT_NAME"
        value = "gpt-4o"
      }

      # Azure AI Search endpoint
      env {
        name  = "AZURE_AI_SEARCH_ENDPOINT"
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

      # Entra ID values used for Easy Auth validation / passing to frontend
      env {
        name  = "ENTRA_CLIENT_ID"
        value = azuread_application.chat_app.client_id
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = data.azuread_client_config.current.tenant_id
      }

      # Signals the app to use ManagedIdentityCredential (not AzureDeveloperCliCredential)
      env {
        name  = "RUNNING_IN_PRODUCTION"
        value = "true"
      }
    }
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 8000
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# Update the Entra app registration redirect URI with the actual Container App URL
resource "azuread_application_redirect_uris" "chat_app_redirect" {
  application_id = azuread_application.chat_app.id
  type           = "Web"
  redirect_uris = [
    "https://${azurerm_container_app.chat.ingress[0].fqdn}/.auth/login/aad/callback"
  ]
}

output "chat_app_url" {
  description = "Chat App public URL"
  value       = "https://${azurerm_container_app.chat.ingress[0].fqdn}"
}
