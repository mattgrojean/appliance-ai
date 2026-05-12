"""
PDF ingestion pipeline — Azure Blob Storage → Azure AI Search (service-manuals index).

What this does:
  1. Lists all .pdf blobs in the storage container (default: "service-manuals")
  2. Downloads each PDF into memory
  3. Extracts text page-by-page with pypdf
  4. Creates one AI Search document per page (chunk = page)
  5. Upserts the chunks into the "service-manuals" index

Blob naming convention (optional but recommended):
  {brand}/{model-series}/filename.pdf  →  brand and model_series auto-detected
  flat/filename.pdf                    →  brand/model_series left empty

Usage (local, after az login):
    cd ai/scripts
    pip install -r requirements.txt
    python ingest_manuals.py

    # Force re-ingest all files even if already indexed:
    python ingest_manuals.py --force

    # Ingest a single blob by path:
    python ingest_manuals.py --blob "samsung/rf28r7351sr/service-manual.pdf"

Environment variables (set these or pass via .env):
    AZURE_STORAGE_ACCOUNT_NAME   e.g. stortechaimsdn...
    AZURE_STORAGE_CONTAINER_NAME  default: service-manuals
    AZURE_AI_SEARCH_ENDPOINT     e.g. https://srch-....search.windows.net
    SEARCH_INDEX_MANUALS         default: service-manuals
    AZURE_TENANT_ID              your Entra tenant ID

In GitHub Actions, the same env vars are set from repository secrets/variables.
Credential resolution:
  - Local:       AzureCliCredential (az login)
  - CI (OIDC):   WorkloadIdentityCredential / DefaultAzureCredential
"""

import argparse
import base64
import io
import os
import re
import sys

from azure.core.credentials import TokenCredential
from azure.identity import AzureCliCredential, DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
from azure.search.documents import SearchClient
from azure.search.documents.models import IndexingResult
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Configuration (from environment / .env)
# ---------------------------------------------------------------------------

STORAGE_ACCOUNT = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME", "")
CONTAINER_NAME = os.environ.get("AZURE_STORAGE_CONTAINER_NAME", "service-manuals")
SEARCH_ENDPOINT = os.environ.get(
    "AZURE_AI_SEARCH_ENDPOINT",
    "https://srch-techai-msdn-dev.search.windows.net",
)
INDEX_NAME = os.environ.get("SEARCH_INDEX_MANUALS", "service-manuals")
TENANT_ID = os.environ.get("AZURE_TENANT_ID", "1ed2126d-597d-465e-b5df-95e96c61399f")


# ---------------------------------------------------------------------------
# Credential helpers
# ---------------------------------------------------------------------------

def get_credential() -> TokenCredential:
    """
    Try AzureCliCredential first (local dev), fall back to DefaultAzureCredential (CI).
    DefaultAzureCredential covers workload identity / managed identity in GitHub Actions.
    """
    try:
        cred = AzureCliCredential(tenant_id=TENANT_ID)
        cred.get_token("https://storage.azure.com/.default")
        print("  auth: AzureCliCredential (az login)")
        return cred
    except Exception:
        print("  auth: DefaultAzureCredential (workload identity / managed identity)")
        return DefaultAzureCredential()


# ---------------------------------------------------------------------------
# Blob helpers
# ---------------------------------------------------------------------------

def list_pdf_blobs(client: BlobServiceClient, blob_filter: str | None) -> list[str]:
    """Return a list of .pdf blob names from the container."""
    container = client.get_container_client(CONTAINER_NAME)
    blobs = [b.name for b in container.list_blobs() if b.name.lower().endswith(".pdf")]
    if blob_filter:
        blobs = [b for b in blobs if b == blob_filter]
    return sorted(blobs)


def download_pdf(client: BlobServiceClient, blob_name: str) -> bytes:
    blob = client.get_blob_client(CONTAINER_NAME, blob_name)
    return blob.download_blob().readall()


# ---------------------------------------------------------------------------
# PDF helpers
# ---------------------------------------------------------------------------

def extract_pages(pdf_bytes: bytes) -> list[str]:
    """Extract text from each page; returns a list of page text strings."""
    try:
        from pypdf import PdfReader
    except ImportError:
        print("ERROR: pypdf is not installed. Run: pip install pypdf>=4.0.0", file=sys.stderr)
        sys.exit(1)

    reader = PdfReader(io.BytesIO(pdf_bytes))
    pages = []
    for page in reader.pages:
        text = page.extract_text() or ""
        pages.append(text.strip())
    return pages


# ---------------------------------------------------------------------------
# Metadata helpers
# ---------------------------------------------------------------------------

def parse_blob_metadata(blob_name: str) -> dict:
    """
    Attempt to extract brand and model_series from the blob path.

    Conventions supported:
      brand/model-series/filename.pdf   → brand="brand", model_series="model-series"
      brand/filename.pdf                → brand="brand", model_series=""
      filename.pdf                      → brand="", model_series=""
    """
    parts = blob_name.split("/")
    if len(parts) >= 3:
        return {"brand": parts[0], "model_series": parts[1]}
    elif len(parts) == 2:
        return {"brand": parts[0], "model_series": ""}
    else:
        return {"brand": "", "model_series": ""}


def make_chunk_id(blob_name: str, page_num: int) -> str:
    """
    Create a stable, URL-safe document ID for a chunk.
    Format: base64url({blob_name}::p{page_num})
    AI Search document keys must be alphanumeric + '-_.'
    """
    raw = f"{blob_name}::p{page_num}"
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


# ---------------------------------------------------------------------------
# Search helpers
# ---------------------------------------------------------------------------

def get_indexed_blob_names(search_client: SearchClient) -> set[str]:
    """Return set of blob names that already have at least one chunk in the index."""
    indexed = set()
    try:
        results = search_client.search(
            search_text="*",
            select=["source_file"],
            top=1000,
        )
        for r in results:
            sf = r.get("source_file")
            if sf:
                indexed.add(sf)
    except Exception as exc:
        print(f"  warning: could not query existing index ({exc}); assuming empty")
    return indexed


def delete_chunks_for_blob(search_client: SearchClient, blob_name: str) -> None:
    """Delete all existing chunks for a blob before re-ingesting."""
    try:
        results = list(
            search_client.search(
                search_text="*",
                filter=f"source_file eq '{blob_name}'",
                select=["id"],
                top=1000,
            )
        )
        if results:
            ids = [{"id": r["id"]} for r in results]
            search_client.delete_documents(documents=ids)
            print(f"  deleted {len(ids)} existing chunks for '{blob_name}'")
    except Exception as exc:
        print(f"  warning: could not delete existing chunks ({exc})")


def upload_chunks(search_client: SearchClient, documents: list[dict]) -> None:
    """Upsert a batch of chunk documents into AI Search."""
    if not documents:
        return
    results: list[IndexingResult] = search_client.upload_documents(documents=documents)
    failed = [r for r in results if not r.succeeded]
    if failed:
        for f in failed:
            print(f"  ❌ failed to index chunk {f.key}: {f.error_message}", file=sys.stderr)
    else:
        print(f"  ✅ indexed {len(documents)} chunks")


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def ingest_blob(
    blob_client: BlobServiceClient,
    search_client: SearchClient,
    blob_name: str,
    force: bool,
    already_indexed: set[str],
) -> int:
    """Download, chunk, and index a single PDF blob. Returns number of chunks created."""
    if not force and blob_name in already_indexed:
        print(f"  ⏭️  skipping '{blob_name}' (already indexed; use --force to re-ingest)")
        return 0

    print(f"  📄 processing '{blob_name}'...")
    pdf_bytes = download_pdf(blob_client, blob_name)
    pages = extract_pages(pdf_bytes)

    if not pages:
        print(f"  ⚠️  no text extracted from '{blob_name}'")
        return 0

    meta = parse_blob_metadata(blob_name)

    if force and blob_name in already_indexed:
        delete_chunks_for_blob(search_client, blob_name)

    documents = []
    for page_num, page_text in enumerate(pages, start=1):
        if not page_text:
            continue  # skip blank pages
        chunk_id = make_chunk_id(blob_name, page_num)
        documents.append(
            {
                "id": chunk_id,
                "source_file": blob_name,
                "brand": meta["brand"],
                "model_series": meta["model_series"],
                "page_number": page_num,
                "chunk_text": page_text,
                "content": page_text,  # mirrors chunk_text for unified search ranking
            }
        )

    upload_chunks(search_client, documents)
    return len(documents)


def run(args: argparse.Namespace) -> None:
    if not STORAGE_ACCOUNT:
        print(
            "ERROR: AZURE_STORAGE_ACCOUNT_NAME is not set.\n"
            "  Set it in your environment or a .env file in ai/scripts/.",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"\n🔍 PDF Ingestion Pipeline")
    print(f"   Storage account : {STORAGE_ACCOUNT}")
    print(f"   Container       : {CONTAINER_NAME}")
    print(f"   Search endpoint : {SEARCH_ENDPOINT}")
    print(f"   Index           : {INDEX_NAME}")
    print(f"   Force re-ingest : {args.force}\n")

    credential = get_credential()

    blob_service = BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
        credential=credential,
    )
    search_client = SearchClient(
        endpoint=SEARCH_ENDPOINT,
        index_name=INDEX_NAME,
        credential=credential,
    )

    blobs = list_pdf_blobs(blob_service, args.blob)
    if not blobs:
        print("No PDF blobs found in container. Upload some PDFs and try again.")
        return

    print(f"Found {len(blobs)} PDF(s):\n")
    already_indexed = get_indexed_blob_names(search_client)

    total_chunks = 0
    for blob_name in blobs:
        total_chunks += ingest_blob(
            blob_service, search_client, blob_name, args.force, already_indexed
        )

    print(f"\n✅ Done — {total_chunks} chunk(s) indexed across {len(blobs)} PDF(s).")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Ingest PDF service manuals from Azure Blob Storage into Azure AI Search."
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-ingest blobs that are already indexed (deletes and re-uploads chunks).",
    )
    parser.add_argument(
        "--blob",
        metavar="BLOB_PATH",
        default=None,
        help="Ingest a single blob by path (e.g. samsung/rf28r7351sr/manual.pdf).",
    )
    run(parser.parse_args())
