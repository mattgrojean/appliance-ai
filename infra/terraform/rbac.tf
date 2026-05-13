# Role-Based Access Control (RBAC)
# All scopes are set at the resource group level so a single assignment covers
# all current and future resources within the group.

locals {
  rg_scope = azurerm_resource_group.ai.id
}

# -------------------------------------------------------
# Current User Access
# -------------------------------------------------------

# Current user → Azure AI Search (create/manage indexes)
resource "azurerm_role_assignment" "current_user_search_contributor" {
  scope                = local.rg_scope
  role_definition_name = "Search Service Contributor"
  principal_id         = "c375126e-2760-4ba8-8cd5-a22812f588ef" # Matthew.Grojean@publix.com
}

# Current user → Azure AI Search (read/write index data)
resource "azurerm_role_assignment" "current_user_search_data_contributor" {
  scope                = local.rg_scope
  role_definition_name = "Search Index Data Contributor"
  principal_id         = "c375126e-2760-4ba8-8cd5-a22812f588ef" # Matthew.Grojean@publix.com
}

# Current user → Storage (upload/read service manual PDFs for local ingestion runs)
resource "azurerm_role_assignment" "current_user_blob_contributor" {
  scope                = local.rg_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = "c375126e-2760-4ba8-8cd5-a22812f588ef" # Matthew.Grojean@publix.com
}

# -------------------------------------------------------
# Function App Permissions
# -------------------------------------------------------

# Function App → Azure AI Search (write/update indexes)
resource "azurerm_role_assignment" "func_search_contributor" {
  scope                = local.rg_scope
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.sync_func_identity.principal_id
}

# Function App → Azure OpenAI (call gpt-4o for enrichment)
resource "azurerm_role_assignment" "func_openai_user" {
  scope                = local.rg_scope
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.sync_func_identity.principal_id
}

# -------------------------------------------------------
# Chat App (Container App) Permissions
# -------------------------------------------------------

# Chat App → Azure AI Search (read/query indexes)
resource "azurerm_role_assignment" "app_search_reader" {
  scope                = local.rg_scope
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.chat_app_identity.principal_id
}

# Chat App → Azure Container Registry (pull the Docker image)
resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = local.rg_scope
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.chat_app_identity.principal_id
}

# Chat App → Azure AI Services (call gpt-4o via Foundry inference endpoint)
resource "azurerm_role_assignment" "app_ai_user" {
  scope                = local.rg_scope
  role_definition_name = "Azure AI User"
  principal_id         = azurerm_user_assigned_identity.chat_app_identity.principal_id
}

# -------------------------------------------------------
# Search Service Permissions
# -------------------------------------------------------

# Search Service system identity → Storage (read service manuals for indexing)
# Consolidated here; the specific knowledge-storage assignment in search.tf also covers this.
resource "azurerm_role_assignment" "search_blob_reader" {
  scope                = local.rg_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_search_service.search.identity[0].principal_id
}

# Search Service system identity → Azure OpenAI (call embedding model in skillset)
# Required so the AzureOpenAIEmbeddingSkill authenticates via managed identity
# with no API key (apiKey and authIdentity left empty in the skill definition).
resource "azurerm_role_assignment" "search_openai_user" {
  scope                = local.rg_scope
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_search_service.search.identity[0].principal_id
}

