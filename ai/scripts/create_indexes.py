"""
One-time script to create Azure AI Search indexes.

Run locally after `terraform apply` has provisioned the search service:

    cd ai/scripts
    pip install -r requirements.txt
    python create_indexes.py

Prerequisites (all set by rbac.tf for your user account):
  - "Search Service Contributor"   — allows creating/managing indexes
  - "Search Index Data Contributor" — allows reading/writing index data

You must be logged in with the same account:
    az login
    # or: azd auth login
"""

import os
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SearchFieldDataType,
    SimpleField,
    SearchableField,
)
from azure.identity import AzureDeveloperCliCredential

SEARCH_ENDPOINT = os.environ.get(
    "AZURE_AI_SEARCH_ENDPOINT",
    "https://srch-techai-msdn-dev.search.windows.net",
)
TENANT_ID = os.environ.get("AZURE_TENANT_ID", "1ed2126d-597d-465e-b5df-95e96c61399f")


def get_client() -> SearchIndexClient:
    # Try az CLI first (most likely for local dev), fall back to azd CLI
    try:
        from azure.identity import AzureCliCredential
        credential = AzureCliCredential(tenant_id=TENANT_ID)
        # Test credential eagerly
        credential.get_token("https://search.azure.com/.default")
        return SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)
    except Exception:
        credential = AzureDeveloperCliCredential(tenant_id=TENANT_ID)
        return SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)


def create_tickets_index(client: SearchIndexClient) -> None:
    """
    repair-tickets: structured fields for Workiz job data.
    Full-text searchable: symptom, technician_notes, fix_summary, content.
    """
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SimpleField(name="job_id", type=SearchFieldDataType.String, filterable=True),
        SimpleField(
            name="appliance_brand",
            type=SearchFieldDataType.String,
            filterable=True,
            facetable=True,
        ),
        SimpleField(name="model_number", type=SearchFieldDataType.String, filterable=True),
        SimpleField(
            name="completion_date",
            type=SearchFieldDataType.DateTimeOffset,
            filterable=True,
            sortable=True,
        ),
        SimpleField(name="zip_code", type=SearchFieldDataType.String, filterable=True),
        SimpleField(
            name="neighborhood",
            type=SearchFieldDataType.String,
            filterable=True,
            facetable=True,
        ),
        SearchableField(name="symptom", type=SearchFieldDataType.String),
        SearchableField(name="technician_notes", type=SearchFieldDataType.String),
        SearchableField(name="fix_summary", type=SearchFieldDataType.String),
        # Combined searchable field used for unified ranking
        SearchableField(name="content", type=SearchFieldDataType.String),
    ]
    index = SearchIndex(name="repair-tickets", fields=fields)
    client.create_or_update_index(index)
    print("✅  Created 'repair-tickets' index")


def create_manuals_index(client: SearchIndexClient) -> None:
    """
    service-manuals: chunked PDF content.
    Full-text searchable: chunk_text, content.
    """
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SimpleField(name="source_file", type=SearchFieldDataType.String),
        SimpleField(name="brand", type=SearchFieldDataType.String, filterable=True),
        SimpleField(
            name="model_series",
            type=SearchFieldDataType.String,
            filterable=True,
        ),
        SimpleField(name="page_number", type=SearchFieldDataType.Int32),
        SearchableField(name="chunk_text", type=SearchFieldDataType.String),
        # content mirrors chunk_text — consistent field name for LLM context formatting
        SearchableField(name="content", type=SearchFieldDataType.String),
    ]
    index = SearchIndex(name="service-manuals", fields=fields)
    client.create_or_update_index(index)
    print("✅  Created 'service-manuals' index")


if __name__ == "__main__":
    print(f"Connecting to: {SEARCH_ENDPOINT}\n")
    client = get_client()
    create_tickets_index(client)
    create_manuals_index(client)
    print("\nDone. Run 'terraform apply' to deploy the Container App when ready.")
