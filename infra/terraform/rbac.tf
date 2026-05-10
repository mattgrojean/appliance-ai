# Role-Based Access Control (RBAC)
# All identities are User-Assigned Managed Identities, so roles can be assigned upfront.

# -------------------------------------------------------
# Function App (Sync) Permissions
# -------------------------------------------------------

# Function App → Azure AI Search (write/update indexes)
resource "azurerm_role_assignment" "func_search_contributor" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.sync_func_identity.principal_id
}

# Function App → Azure OpenAI (optional, if sync function calls gpt-4o for enrichment)
resource "azurerm_role_assignment" "func_openai_user" {
  scope                = azurerm_cognitive_account.ai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.sync_func_identity.principal_id
}

# -------------------------------------------------------
# Chat App (Container App) Permissions
# -------------------------------------------------------

# Chat App → Azure AI Search (read/query indexes)
resource "azurerm_role_assignment" "app_search_reader" {
  scope                = azurerm_search_service.search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.chat_app_identity.principal_id
}

# Chat App → Azure OpenAI (call gpt-4o model)
resource "azurerm_role_assignment" "app_openai_user" {
  scope                = azurerm_cognitive_account.ai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.chat_app_identity.principal_id
}

