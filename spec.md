This specification is designed for an "Agentic-Lite" architecture. It uses the Assistants API (v2) to handle the "Second Brain" heavy lifting (File Search/RAG) without you having to manage a vector database, while keeping the orchestration in a simple, CLI-deployable Python environment.

Specification: Appliance SEO Agentic Pipeline (ASAP)
1. High-Level Architecture
The goal is to transform technical job data into public-facing SEO content while maintaining a "Human-in-the-Loop" for quality control and proprietary protection.

Ingestion: Workiz Webhook (Job Completion).

Brain: Azure OpenAI Assistant (v2) with File Search enabled (storing Service Manuals + Historical Fixes).

Orchestrator: Azure Function (Python) or a standalone containerized script.

Review Layer: Google Sheets (Acting as a lightweight "CMS Drafts" area).

Publishing: Wix CMS (via Velo/Wix HTTP Functions).

2. Feature Set & Justification
A. Managed Context (The "Second Brain")
Feature: File Search (Vector Store) integration.

Justification: Instead of manual RAG, we upload PDFs of service manuals and .md files of repair notes directly to the Assistant’s Vector Store.

User Value: The system "remembers" that a specific Samsung model has a common thermistor failure without you hard-coding that knowledge.

B. "Secret Sauce" Filtering & SEO Personas
Feature: System Prompt Guardrails.

Justification: The prompt explicitly instructs the LLM to write for a "Homeowner" persona.

Constraint: "Describe the symptom (e.g., 'Fridge not cooling') and the outcome ('Restored to factory temp'), but redact specific diagnostic voltages, hidden service menus, or proprietary tool use."

C. GEO-Mapping Injection
Feature: Localized Neighborhood Mapping.

Justification: Search engines prioritize neighborhood-level relevance over city-level.

Logic: A JSON map in the code converts zip codes (from Workiz) into neighborhood names (e.g., 33919 -> McGregor/Cypress Lake). This is injected into the blurb: "Another successful repair in the McGregor area..."

3. Data Schema (For LLM Ingestion)
To ensure Copilot/Cursor generates clean code, use this Pydantic-style schema for the payload:

Python
class RepairJob(BaseModel):
    job_id: str
    appliance_brand: str
    model_number: str
    zip_code: str
    neighborhood: str  # Resolved via lookup table
    technician_notes: str # The "Raw" input from Workiz
    completion_date: datetime

class SEOPost(BaseModel):
    title: str  # e.g., "LG Refrigerator Repair in Fort Myers"
    blurb: str  # The 150-word public summary
    keywords: List[str] # ["LG Repair", "Fort Myers Appliance Service", "Neighborhood"]
    status: str = "Pending_Review"
4. Implementation Steps (CLI / Dev Workflow)
Phase 1: The Assistant Setup (CLI)
Use the OpenAI/Azure CLI to create the Assistant. This avoids ClickOps and allows for repeatable deployments.

Tool: file_search enabled.

Temperature: 0.7 (Enough for varied writing, low enough for technical accuracy).

Phase 2: The Logic (Python Orchestrator)
The script should perform the following "Pass":

Receive Webhook: Validate the Workiz signature.

Enhance Context: Query the Assistant Thread with: "Based on these tech notes and your uploaded manuals for {model_number}, write a short public blurb about the fix. Protect the 'secret sauce' as per instructions."

GEO-Tag: Append the neighborhood name to the draft.

Append to Review Sheet: Use the Google Sheets API to add a row.

Phase 3: The Wix Bridge
Create a hidden HTTP Function in Wix (Velo) that accepts a JSON payload.

Endpoint: POST /_functions/publishRepair

Action: Creates a new item in the "Repair History" Collection.

5. Helpful Tips for Long-Term Maintenance
The "One-Click" Approval: In the Google Sheet, add a checkbox column titled "Publish." Set up a secondary script (or a basic Make.com scenario) that watches for that checkbox. When checked, it pushes to Wix. This is the lowest management overhead way to keep a human in the loop.

Avoid "Over-Agenting": Don't try to make the AI look up parts live during the SEO generation. Keep the "SEO Brain" separate from the "Technical Diagnostic Brain" to avoid hallucinations in public posts.

Assistant Versioning: When you get a new batch of manuals, don't delete the old ones. Use the Assistant's Vector Store to keep a rolling "Memory" of every appliance generation.

Wix SEO: Ensure your Wix Collection is set to "Dynamic Pages." This way, every fix becomes its own URL (e.g., mysite.com/repairs/samsung-dryer-fort-myers), which is the gold standard for GEO-visibility.

6. Prompt for your AI Coding Assistant (Copilot/Antigravity)
"Write a Python Azure Function that triggers on a webhook from Workiz. It should use the Azure OpenAI Assistants API (v2) with File Search to process appliance repair notes. Resolve the zip code to a neighborhood name using a dictionary, generate a 150-word SEO-friendly blurb that redacts proprietary technical steps, and append the result to a Google Sheet for review. Use Pydantic for data validation."

This approach gives you the CLI-driven control you enjoy, but the managed services (Assistants + Sheets) ensure that if you step away, the system doesn't require a senior engineer to keep it running.