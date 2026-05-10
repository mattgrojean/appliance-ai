# Azure AI Services Account and Foundry Project
# This is the core "brain" — provides OpenAI models, vector search, and more
resource "azurerm_cognitive_account" "ai" {
  name                       = "aafa-${var.project_name}-${var.environment}"
  location                   = azurerm_resource_group.ai.location
  resource_group_name        = azurerm_resource_group.ai.name
  kind                       = "AIServices"
  sku_name                   = "S0"
  project_management_enabled = true
  custom_subdomain_name      = "ais-${var.project_name}-${var.environment}"

  identity {
    type = "SystemAssigned"
  }
}

# AI Foundry Project — a workspace inside the AI Services Account
resource "azurerm_cognitive_account_project" "project" {
  name                 = "aafp-${var.project_name}-${var.environment}"
  cognitive_account_id = azurerm_cognitive_account.ai.id
  location             = azurerm_resource_group.ai.location
  display_name         = "Appliance AI Project"
  description          = "Azure AI Foundry Project for technician chat & SEO pipeline"

  identity {
    type = "SystemAssigned"
  }
}

# Model Deployment: gpt-4o
# GlobalStandard routes traffic across regions for better availability.
# Capacity = thousands of tokens per minute; 10 = 10K TPM (suitable for dev).
resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.ai.id
  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = "2024-11-20"
  }
  sku {
    name     = "GlobalStandard"
    capacity = 10
  }
}

# Outputs for SDK/app configuration
output "openai_endpoint" {
  description = "Azure OpenAI endpoint URL"
  value       = azurerm_cognitive_account.ai.endpoint
}

output "openai_resource_name" {
  description = "Azure OpenAI account name (used in some SDK configurations)"
  value       = azurerm_cognitive_account.ai.name
}

output "foundry_project_name" {
  description = "AI Foundry project name"
  value       = azurerm_cognitive_account_project.project.name
}
