# How This Works — Appliance AI

A reference guide for the Appliance AI technician chat app — architecture, infrastructure,
credentials, and deployment steps. Everything is managed with **Terraform**.

---

## What We Built

A mobile-friendly chat app for appliance repair technicians. Technicians can describe a
problem, and the AI searches past repair tickets and service manuals to give a practical answer.

```
Technician (phone browser)
    │
    ▼ HTTPS + Entra ID login
Azure Container Apps  (Python FastAPI + HTML/JS)
    │
    ├──→ Azure AI Inference (gpt-4o via AI Foundry)  ← answers questions
    │
    └──→ Azure AI Search
             ├── Index: repair-tickets   ← past Workiz jobs
             └── Index: service-manuals  ← PDF manuals (chunked)
                          ▲
                    Nightly sync
                    Azure Function (Timer)
                          │
                     Workiz REST API
```

---

## All Deployed Resources

| Resource | Name | Purpose |
|---|---|---|
| Resource Group | `rg-techai-msdn-dev` | Container for all project resources |
| AI Services Account | `aafa-techai-msdn-dev` | Unified AI hub (OpenAI models + AI Foundry) |
| AI Foundry Project | `aafp-techai-msdn-dev` | Workspace inside the AI account |
| Model Deployment | `gpt-4o` | The LLM — `GlobalStandard`, 10K TPM |
| Azure AI Search | `srch-techai-msdn-dev` | Full-text search over tickets + manuals |
| Container Registry | `acrtechaimsdndev` | Stores Docker image for the chat app |
| Container Apps Env | `cae-techai-msdn-dev` | Hosts the FastAPI container (scales to zero) |
| Function App | `func-techai-msdn-dev-sync` | Nightly Workiz sync (timer trigger) |
| Log Analytics | `log-techai-msdn-dev` | Logs for Container Apps + Function App |
| Storage Account | `stortechaimsdndevfunc01` | Function App state storage |
| UAMI (chat) | `uami-techai-msdn-dev-chat` | Identity for the Container App |
| UAMI (sync) | `uami-techai-msdn-dev-sync` | Identity for the Function App |
| Entra App | `app-techai-msdn-dev-chat` | Entra ID registration for Easy Auth |

**Region note:** All resources are in `East US 2`, except AI Search which is in
`Sweden Central` (eastus2 was out of capacity when initially deployed).

---

## Key Endpoints

| What | URL |
|---|---|
| Inference endpoint (ChatCompletionsClient) | `https://ais-techai-msdn-dev.services.ai.azure.com/models` |
| AI Foundry project endpoint | `https://ais-techai-msdn-dev.services.ai.azure.com/api/projects/aafp-techai-msdn-dev` |
| OpenAI / cognitiveservices endpoint | `https://ais-techai-msdn-dev.cognitiveservices.azure.com/` |
| AI Search endpoint | `https://srch-techai-msdn-dev.search.windows.net` |

The **inference endpoint** uses `services.ai.azure.com/models` — this is what the
`azure-ai-inference` SDK (`ChatCompletionsClient`) expects. It's different from the
older `cognitiveservices.azure.com` endpoint used by the `openai` package.

---

## SDK Pattern

We use `azure-ai-inference` (not the `openai` package) — it aligns with the AI Foundry
project and uses standard Azure identity auth.

```python
from azure.ai.inference.aio import ChatCompletionsClient
from azure.identity.aio import AzureCliCredential, ManagedIdentityCredential

# Local dev: uses your 'az login' session
credential = AzureCliCredential(tenant_id="1ed2126d-...")

# Production: uses the Container App's User-Assigned Managed Identity
credential = ManagedIdentityCredential(client_id="af0ad523-...")  # UAMI client_id

client = ChatCompletionsClient(
    endpoint="https://ais-techai-msdn-dev.services.ai.azure.com/models",
    credential=credential,
    credential_scopes=["https://cognitiveservices.azure.com/.default"],  # required for AI Foundry MaaS
)
```

**Important:** In production we use `ManagedIdentityCredential(client_id=UAMI_CLIENT_ID)`.
The `AZURE_CLIENT_ID` env var on the Container App is the UAMI's **client_id**
(`af0ad523-a71e-42ba-892b-93953dfdd323`) — NOT the Entra app registration client_id
and NOT the principal_id.

---

## Authentication (Two Separate Concepts)

### 1. App-to-Azure (credential for calling APIs)
The Container App uses a **User-Assigned Managed Identity (UAMI)** to call Azure services
without any passwords or secrets. Roles assigned in `rbac.tf`:

| Identity | Role | Service |
|---|---|---|
| Chat App UAMI | `Search Index Data Reader` | AI Search |
| Chat App UAMI | `Azure AI User` | AI Services (covers MaaS + OpenAI endpoints) |
| Chat App UAMI | `AcrPull` | Container Registry |
| Sync Func UAMI | `Search Index Data Contributor` | AI Search |
| Sync Func UAMI | `Cognitive Services OpenAI User` | AI Services |
| Your user account | `Azure AI User` | AI Services (portal access) |
| Your user account | `Search Service Contributor` | AI Search (create indexes) |
| Your user account | `Search Index Data Contributor` | AI Search (load data locally) |

### 2. User Login (who can use the chat app)
The Container App uses **Azure Container Apps Easy Auth** with Microsoft Entra ID.
Users are redirected to `/.auth/login/aad` and must sign in with their company account.
After login, Container Apps injects the `X-Ms-Client-Principal-Name` header into every
request so the backend knows who is asking.

Easy Auth is configured after `terraform apply` with one `az` command (see Deployment
section below).

---

## Azure AI Search — Important Config

### RBAC Auth Must Be Enabled
By default, AI Search is in `apiKeyOnly` mode — RBAC tokens are rejected. To allow
managed identities and `az login` credentials, the service must be set to `aadOrApiKey`.

This is configured in Terraform via:
```hcl
authentication_failure_mode = "http401WithBearerChallenge"
```
...and was also set manually via `az search service update` for the initially deployed service.

### Free Tier Limits
- 50 MB storage, 3 indexes max, no semantic/vector search
- Two of the 3 index slots are used: `repair-tickets` and `service-manuals`
- Upgrade to `standard` SKU (~$250/mo) when you need semantic ranking or more data

---

## Terraform File Structure

```
infra/terraform/
├── locals.tf           # Computed local values (naming conventions)
├── providers.tf        # Provider versions (azurerm, azuread, azapi)
├── backend.tf          # Remote state config (azurerm storage)
├── variables.tf        # Input variable declarations
├── resource_group.tf   # Resource group
├── identity.tf         # UAMIs + Entra app registration
├── rbac.tf             # All role assignments
├── agent.tf            # AI Services account, Foundry project, gpt-4o deployment
├── search.tf           # Azure AI Search service
├── storage.tf          # Storage account (for Function App)
├── registry.tf         # Container Registry (ACR)
├── observability.tf    # Log Analytics workspace
├── compute.tf          # Container Apps environment + Function App
├── web.tf              # Container App (commented out until image is built)
└── environments/
    └── dev/
        ├── dev.tfvars              # Variable values for dev
        ├── dev-backend-config.json # Remote state backend config
        └── dev-backend-config-personal.json
```

---

## Application File Structure

```
ai/
├── app/
│   ├── main.py          # FastAPI backend — lifespan pattern, SSE streaming
│   ├── chat.py          # ChatCompletionsClient wrapper — azure-ai-inference SDK
│   ├── search.py        # SearchClient wrapper — full-text search both indexes
│   ├── requirements.txt # Python deps
│   ├── Dockerfile       # python:3.11-slim, uvicorn on port 8000
│   ├── .env.sample      # Copy to .env for local dev
│   └── static/
│       └── index.html   # Mobile-first chat UI (vanilla HTML/JS)
├── scripts/
│   ├── create_indexes.py  # Creates AI Search indexes (run once)
│   ├── ingest_manuals.py  # PDF ingestion pipeline (run to load/refresh manuals)
│   └── requirements.txt
└── sync/
    └── workiz_sync.py   # Nightly Azure Function (not yet built)
```

---

## SSE Streaming Format

The `/chat` endpoint returns a text/event-stream response. Each event is a JSON line:

```
data: {"content": "The likely cause...", "type": "message"}

data: {"content": " check the capacitor.", "type": "message"}

data: {"type": "stream_end"}

```

The frontend uses `fetch()` + `response.body.getReader()` (not `EventSource`) to read the
stream, because `EventSource` doesn't support `POST` requests with a body.

---

## How to Deploy (Step by Step)

### Prerequisites
- `az login` (Azure CLI)
- Docker or `az acr build` access
- Terraform initialized: `terraform init -backend-config="environments\dev\dev-backend-config.json"`

### Step 1 — Create AI Search Indexes (one-time)
```powershell
cd ai/scripts
python create_indexes.py
```

### Step 2 — Build and Push Docker Image
```powershell
# From repo root — builds the image and pushes to ACR (no local Docker required)
az acr build `
  --registry acrtechaimsdndev `
  --image appliance-ai-chat:latest `
  ai/app
```

### Step 3 — Uncomment Container App in web.tf, then apply
Edit `infra/terraform/web.tf` — remove the `/* ... */` comment block around the Container App.

```powershell
cd infra/terraform
terraform apply -var-file="environments/dev/dev.tfvars"
```

### Step 4 — Enable Easy Auth (done via `az rest` — see Known Issues below)

Easy Auth is configured directly via the ARM REST API because `az containerapp auth` CLI
commands hang indefinitely in this environment. The configuration was applied once with
`az rest --method PUT` and is now persisted on the Container App — no re-running needed.

**What was configured:**
- Provider: Azure Active Directory (Microsoft Entra ID)
- Entra app client_id: `81db3625-6ac3-4a12-994a-ba5bcf898046`
- Tenant: `1ed2126d-597d-465e-b5df-95e96c61399f`
- Unauthenticated action: Redirect to login page
- Callback URL: `https://ca-techai-msdn-dev.lemonisland-10a85b1c.eastus2.azurecontainerapps.io/.auth/login/aad/callback`

### Step 5 — Test
```powershell
# Health check (no auth required)
curl https://ca-techai-msdn-dev.lemonisland-10a85b1c.eastus2.azurecontainerapps.io/health
# Returns: {"status": "ok"}

# App UI (requires Microsoft login)
# Open in browser:
# https://ca-techai-msdn-dev.lemonisland-10a85b1c.eastus2.azurecontainerapps.io
```

---

## Local Development

```powershell
cd ai/app

# Copy sample env and fill in values
Copy-Item .env.sample .env
# (edit .env — all values are already pre-filled for this project)

# Install dependencies
pip install -r requirements.txt

# Run locally
uvicorn main:app --reload

# Open in browser
# http://localhost:8000
```

The app uses `AzureCliCredential` locally (reads from your `az login` session).
No local emulators needed — it talks directly to the real Azure resources.

---

## PDF Ingestion Pipeline

This is how service manual PDFs get from your computer/portal into AI Search so the
chatbot can cite them.

### Flow

```
You upload a PDF
    ↓
Azure Blob Storage (container: "service-manuals")
    e.g. samsung/rf28r7351sr/service-manual.pdf
    ↓
ingest_manuals.py (runs locally or via GitHub Actions)
    ├── downloads each .pdf blob
    ├── extracts text page-by-page with pypdf
    ├── one chunk = one page
    └── upserts into AI Search "service-manuals" index
              ↓
        search.py retrieves chunks at query time
              ↓
        format_context() formats "[Service Manual — filename, p.N] ..."
              ↓
        LLM sees the citation and can reference it in the answer
```

### Blob naming convention

Upload PDFs following this path pattern for automatic brand/model tagging:

```
{brand}/{model-series}/filename.pdf      →  brand and model_series auto-detected
filename.pdf                             →  brand and model_series left blank
```

Examples:
- `samsung/rf28r7351sr/service-manual.pdf` → brand=samsung, model_series=rf28r7351sr
- `whirlpool/wdt750sahz/parts-diagram.pdf` → brand=whirlpool, model_series=wdt750sahz

### Upload a PDF

```powershell
# Via Azure CLI (requires Storage Blob Data Contributor role)
az storage blob upload `
  --account-name stortechaimsdndevfunc01 `
  --container-name service-manuals `
  --name "samsung/rf28r7351sr/service-manual.pdf" `
  --file "C:\path\to\service-manual.pdf" `
  --auth-mode login
```

Or drag and drop via the Azure Portal → Storage Account → service-manuals container.

### Run the ingestion script locally

```powershell
cd ai/scripts
pip install -r requirements.txt

# Set required env vars (or put them in a .env file here)
$env:AZURE_STORAGE_ACCOUNT_NAME = "stortechaimsdndevfunc01"
$env:AZURE_AI_SEARCH_ENDPOINT   = "https://srch-techai-msdn-dev.search.windows.net"

# Ingest all new PDFs (skips already-indexed blobs)
python ingest_manuals.py

# Force re-ingest everything (deletes old chunks, re-uploads)
python ingest_manuals.py --force

# Ingest a single blob
python ingest_manuals.py --blob "samsung/rf28r7351sr/service-manual.pdf"
```

### Run via GitHub Actions

1. Go to your GitHub repo → **Actions** tab → **Ingest Service Manuals**
2. Click **Run workflow**
3. Optionally set "Force re-ingest" or "Single blob path"

For first-time GitHub Actions setup, see the comments at the top of
`.github/workflows/ingest-manuals.yml` — you need to configure OIDC federated
credentials and four repository secrets (`AZURE_TENANT_ID`, `AZURE_CLIENT_ID`,
`AZURE_SUBSCRIPTION_ID`) plus two variables (`AZURE_STORAGE_ACCOUNT_NAME`,
`AZURE_AI_SEARCH_ENDPOINT`).

### How citations appear in responses

`format_context()` in `search.py` formats manual chunks as:

```
[Service Manual — samsung/rf28r7351sr/service-manual.pdf, p.12] Samsung RF28R7351SR: ...
```

The LLM receives this as context and can reference the source in its answer. The chatbot
doesn't auto-format footnotes (that would require structured output), but it can say
things like "According to the Samsung RF28 service manual, page 12..." naturally.

### Chunking strategy (current: page-based)

One chunk = one PDF page. This works well for service manuals where each page tends
to be a self-contained topic. For very dense or sparse pages, consider upgrading to
sliding-window chunking later.

---


| AI Search | `srch-techai-msdn-dev` (Sweden Central, free tier) |
| AI Inference | `https://ais-techai-msdn-dev.services.ai.azure.com/models` |
| Model | `gpt-4o` v`2024-11-20`, GlobalStandard, 10K TPM |
| Chat UAMI client_id | `af0ad523-a71e-42ba-892b-93953dfdd323` |
| Entra tenant | `1ed2126d-597d-465e-b5df-95e96c61399f` |
| Entra app | `81db3625-6ac3-4a12-994a-ba5bcf898046` |
| AI Search indexes | `repair-tickets`, `service-manuals` (created ✅) |
| Container App | `https://ca-techai-msdn-dev.lemonisland-10a85b1c.eastus2.azurecontainerapps.io` ✅ |
| Container App image | `acrtechaimsdndev.azurecr.io/appliance-ai-chat:latest` ✅ |
| Easy Auth | Enabled — redirects unauthenticated users to AAD login ✅ |


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

---

## Known Issues / Lessons Learned

### `aiohttp` must be in requirements.txt

`azure-identity[aio]` (the async version) requires `aiohttp` as a transport. It is NOT
automatically installed as a transitive dependency. Without it, the Container App crashes
on startup with:

```
ImportError: aiohttp package is not installed
```

**Fix:** Always include `aiohttp>=3.9.0` in `requirements.txt` when using async Azure SDK
clients (`azure.identity.aio`, `azure.ai.inference.aio`, etc.).

---

### `az containerapp` CLI hangs on all commands

Every `az containerapp` command (show, delete, auth update, secret set) hangs indefinitely
in this environment. Root cause unknown — possibly an extension version or network issue.

**Workaround:** Use `az rest` with the ARM management API for all Container App operations:

```powershell
# GET
az rest --method GET --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.App/containerApps/$ca?api-version=2024-03-01"

# PUT (update whole resource)
az rest --method PUT --url "..." --body "@$tmpFile"

# PATCH (update secrets)
az rest --method PATCH --url "..." --body "@$tmpFile"

# Auth config
az rest --method PUT --url ".../authConfigs/current?api-version=2024-03-01" --body "@$tmpFile"
```

**Important when doing a PUT:** The GET response strips secret values (they come back as
`{name: "foo"}` with no `value`). You must manually re-add secret values before PUT-ing
the resource back, or Azure returns `ContainerAppSecretInvalid`.

---

### Failed Terraform applies leave partial Azure resources

When `terraform apply` fails mid-run, Azure resources may be partially created but not
reflected in Terraform state. On the next `apply` you get "resource already exists".

**Solutions:**
- If the resource is healthy: `terraform import <resource_type>.<name> <azure_resource_id>`
- If the resource is in a bad state: delete via `az rest --method DELETE`, then re-apply

---

### Container App `traffic_weight` — `percent` renamed to `percentage`

In recent versions of the `azurerm` provider, the `traffic_weight` block renamed `percent`
to `percentage`. Use `percentage = 100`.

---

### ACR pull requires explicit `registry` block

The Container App UAMI needs not just the `AcrPull` role on ACR, but also an explicit
`registry` block in the Terraform resource:

```hcl
registry {
  server   = azurerm_container_registry.acr.login_server
  identity = azurerm_user_assigned_identity.chat.id
}
```

Without this, the Container App gets `UNAUTHORIZED` pulling from ACR even with the role assigned.

---

### `Cognitive Services OpenAI User` does NOT cover the MaaS inference endpoint

The classic OpenAI role (`Cognitive Services OpenAI User`) only covers the
`cognitiveservices.azure.com` endpoint. The AI Foundry MaaS endpoint
(`services.ai.azure.com/models`) requires the **`Azure AI User`** role, which grants the
wildcard data action `Microsoft.CognitiveServices/*`.

**Symptom:** 500 with `PermissionDenied: lacks the required data action
Microsoft.CognitiveServices/accounts/MaaS/chat/completions/action`

**Fix in `rbac.tf`:** Replace `Cognitive Services OpenAI User` with `Azure AI User` for
the chat app UAMI on the AI Services account.

---

### `credential_scopes` for AI Foundry MaaS endpoint

When using `ChatCompletionsClient` with `services.ai.azure.com/models`, use:
```python
credential_scopes=["https://cognitiveservices.azure.com/.default"]
```
NOT `https://ai.azure.com/.default`. While both scopes are documented, only
`cognitiveservices.azure.com/.default` works correctly with `ManagedIdentityCredential`
for the MaaS data plane.

---

### `azure-search-documents` async `search()` must be `await`-ed

In `azure-search-documents` >= 11.6.x, the async `search()` method became a coroutine.
You must `await` it before iterating:

```python
# WRONG (worked in 11.4.x, breaks in 11.6.x+)
async for result in client.search(**kwargs): ...

# CORRECT
async for result in await client.search(**kwargs): ...
```

