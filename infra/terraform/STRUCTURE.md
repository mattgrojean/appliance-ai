# Terraform File Structure

The infrastructure is now organized by logical component for maintainability and clarity.

## Files & Purpose

### Core Files

- **`main.tf`** — Documentation only. All resources moved to component files.
- **`providers.tf`** — Provider configuration (azurerm, azuread).
- **`variables.tf`** — Input variables (subscription_id, location, environment, workiz_api_key).
- **`locals.tf`** — Common naming conventions and tags.
- **`backend.tf`** — Remote state configuration (Azure Storage backend).

### Infrastructure Components

#### 1. Base Infrastructure
- **`resource_group.tf`** — Azure Resource Group container for all resources.

#### 2. AI & Models
- **`agent.tf`** — Azure AI Services Account, AI Foundry Project, gpt-4o deployment.

#### 3. Knowledge Layer
- **`search.tf`** — Azure AI Search (free tier for dev, supports semantic search on upgrade).

#### 4. Storage & Registry
- **`storage.tf`** — Storage Account for Function App state & triggers.
- **`registry.tf`** — Azure Container Registry for Docker images.

#### 5. Compute & Runtime
- **`observability.tf`** — Log Analytics Workspace (centralized logging).
- **`compute.tf`** — Container Apps Environment, Function App (nightly sync timer).

#### 6. Identity & Access
- **`identity.tf`** — Entra ID app registration for chat app authentication.
- **`rbac.tf`** — Role assignments (least-privilege access for managed identities).

## How to Navigate

**Looking for a specific resource?**
- **Chat web app hosting?** → `compute.tf`
- **Model deployment config?** → `agent.tf`
- **Search indexes?** → `search.tf`
- **User authentication?** → `identity.tf`
- **Access permissions?** → `rbac.tf`

## Running Terraform

```powershell
cd infra/terraform

# Initialize (downloads providers and connects to remote state)
terraform init -backend-config="environments\dev\dev-backend-config.json"

# Preview changes
terraform plan -var-file="environments\dev\dev.tfvars"

# Apply changes
terraform apply -var-file="environments\dev\dev.tfvars"

# Check outputs
terraform output
```

## Adding a New Component

When adding a new service (e.g., a database, new function app):
1. Create a new `.tf` file named after the component (e.g., `database.tf`)
2. Add resource definitions and relevant outputs
3. If it needs access control, add role assignments to `rbac.tf`
4. Run `terraform plan` to validate
