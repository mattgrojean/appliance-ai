# How This Works — Appliance AI Infrastructure

A reference guide for the Azure infrastructure that backs the Appliance SEO Agentic
Pipeline (ASAP). Everything here is deployed and managed with **Terraform**.

---

## What's Deployed

```
Azure Subscription: Visual Studio Enterprise (ab35a678-...)
└── Resource Group: rg-techai-msdn-dev  (Central US)
    └── Azure AI Services Account: aafa-techai-msdn-dev
        ├── AI Foundry Project: aafp-techai-msdn-dev
        └── Model Deployment: gpt-4o (2024-11-20, GlobalStandard, 10K TPM)
```

### Resource-by-resource breakdown

| Resource | Name | Why it exists |
|---|---|---|
| Resource Group | `rg-techai-msdn-dev` | Container for all project resources. Named `rg-{project}-{env}`. |
| Azure AI Services Account | `aafa-techai-msdn-dev` | The hub — provides access to OpenAI models, File Search (vector store), and the Assistants API. Kind `AIServices` is the new unified account type (replaces the old `OpenAI`-only kind). |
| AI Foundry Project | `aafp-techai-msdn-dev` | A workspace inside the AI Services account. Organizes deployments, indexes, and experiments. Think of it as a "folder" for your AI work. |
| Model Deployment | `gpt-4o` | The actual LLM endpoint your code calls. Deployed inside the AI Services account. |

---

## Why These Choices?

### Azure AI Services (`kind = "AIServices"`)
The newer unified account kind. It gives you:
- OpenAI model access (GPT-4o, etc.)
- Azure AI Search integration
- File Search / vector store (used by the Assistants API for the "Second Brain" RAG)

### `project_management_enabled = true`
Unlocks the AI Foundry Project resource (`azurerm_cognitive_account_project`). Without
this, you can't create projects inside the account.

### `custom_subdomain_name`
Required for the AI Services account to get its own HTTPS endpoint:
`https://ais-techai-msdn-dev.cognitiveservices.azure.com/`

### Model: `gpt-4o` version `2024-11-20`
- Most capable generally-available GPT-4o release as of May 2026.
- Supports the Assistants API v2, including File Search (needed for the spec's "Second
  Brain" pattern).

### SKU: `GlobalStandard` (not `Standard`)
`GlobalStandard` routes your requests across Azure regions for better availability and
higher throughput. It's the recommended SKU for most production and dev workloads.
`Standard` is single-region and has much lower rate limits.

### Capacity: `10` (= 10,000 tokens per minute)
Capacity is measured in **thousands of tokens per minute (TPM)**. 10K TPM is plenty for
dev/testing — a typical repair-job SEO blurb is ~500 tokens in + ~300 tokens out.
Increase this if you process jobs in bulk.

---

## Terraform Structure

```
infra/
└── terraform/
    ├── main.tf                  # Resource definitions (what gets created)
    ├── variables.tf             # Input variable declarations
    ├── providers.tf             # Provider config (azurerm ~> 4.0)
    ├── backend.tf               # Remote state backend (azurerm storage)
    └── environments/
        ├── dev/
        │   ├── dev.tfvars                    # Variable values for dev
        │   ├── dev-backend-config.json       # Backend config (MSDN sub)
        │   └── dev-backend-config-personal.json  # Backend config (personal sub)
        └── prd/
            └── (production config)
```

### How the backend works

Terraform state is stored **remotely** in an Azure Storage Account, not on your local
disk. This means:
- The state is shared (teammates or CI/CD can run Terraform too)
- State is not lost if you switch machines

The backend is configured in two parts:

1. `backend.tf` — declares that we use the `azurerm` backend (no values hardcoded):
   ```hcl
   terraform {
     backend "azurerm" {}
   }
   ```

2. `dev-backend-config.json` — provides the actual values at `terraform init` time:
   ```json
   {
     "subscription_id": "...",
     "resource_group_name": "terraform-uc-dev-01",
     "storage_account_name": "sadevtechaitf01",
     "container_name": "terraform-state-files",
     "key": "appliance-ai/terraform.tfstate",
     "use_azuread_auth": true
   }
   ```
   `use_azuread_auth: true` means Terraform authenticates using your Azure CLI login
   (no storage account keys needed).

---

## How to Deploy

### First time (or after switching machines)

```powershell
cd infra/terraform

# 1. Initialize — downloads providers, connects to remote state
terraform init -backend-config="environments\dev\dev-backend-config.json"

# 2. Preview what will change
terraform plan -var-file="environments\dev\dev.tfvars"

# 3. Apply the changes
terraform apply -var-file="environments\dev\dev.tfvars"
```

### Subsequent runs

If the backend is already initialized, you can skip `-reconfigure`:

```powershell
terraform plan -var-file="environments\dev\dev.tfvars"
terraform apply -var-file="environments\dev\dev.tfvars" -auto-approve
```

### Tear down

```powershell
terraform destroy -var-file="environments\dev\dev.tfvars"
```

---

## How Your Code Connects to the Model

After deployment, your Python code calls the model via the AI Services endpoint. The
endpoint URL follows this pattern:

```
https://ais-{project_name}-{environment}.cognitiveservices.azure.com/
```

For dev:
```
https://ais-techai-msdn-dev.cognitiveservices.azure.com/
```

Using the `openai` Python SDK with Azure:

```python
from openai import AzureOpenAI

client = AzureOpenAI(
    azure_endpoint="https://ais-techai-msdn-dev.cognitiveservices.azure.com/",
    api_version="2024-05-01-preview",   # Required for Assistants API v2
    # Use DefaultAzureCredential for passwordless auth (recommended)
    # or api_key="..." for quick testing
)

# Create an assistant with File Search (the "Second Brain")
assistant = client.beta.assistants.create(
    model="gpt-4o",          # Must match the deployment name in Terraform
    tools=[{"type": "file_search"}],
    instructions="You are an appliance repair SEO writer...",
)
```

The **deployment name** (`gpt-4o`) in your SDK call must match the `name` field of
`azurerm_cognitive_deployment` in `main.tf`.

---

## Current State (as of May 2026)

| Field | Value |
|---|---|
| Subscription | `ab35a678-...` (Visual Studio Enterprise) |
| Resource Group | `rg-techai-msdn-dev` |
| Region | `Central US` |
| AI Services Account | `aafa-techai-msdn-dev` |
| AI Foundry Project | `aafp-techai-msdn-dev` |
| Model | `gpt-4o` v`2024-11-20` |
| SKU | `GlobalStandard` |
| Capacity | 10K TPM |
