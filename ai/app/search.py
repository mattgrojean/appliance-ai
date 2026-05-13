"""
Azure AI Search wrapper — full-text search across both knowledge indexes.

Credential pattern:
  - Production: ManagedIdentityCredential (UAMI) — set by get_credential() in chat.py
  - Local dev:  AzureDeveloperCliCredential via az login
"""

import os
from azure.search.documents.aio import SearchClient
from azure.core.credentials_async import AsyncTokenCredential

SEARCH_ENDPOINT = os.environ.get("AZURE_AI_SEARCH_ENDPOINT", "")
INDEX_TICKETS = os.environ.get("SEARCH_INDEX_TICKETS", "repair-tickets")
INDEX_MANUALS = os.environ.get("SEARCH_INDEX_MANUALS", "service-manuals")


async def search_both_indexes(
    query: str,
    credential: AsyncTokenCredential,
    brand: str = "",
    top: int = 5,
) -> list[dict]:
    """
    Search repair-tickets and service-manuals indexes.
    Results are merged and sorted by relevance score descending.
    """
    results = []
    brand_filter = f"appliance_brand eq '{brand}'" if brand else None
    manual_filter = f"brand eq '{brand}'" if brand else None

    async with SearchClient(SEARCH_ENDPOINT, INDEX_TICKETS, credential) as client:
        kwargs: dict = {"search_text": query, "top": top}
        if brand_filter:
            kwargs["filter"] = brand_filter
        async for r in await client.search(**kwargs):
            results.append({**r, "_source": "ticket", "_score": r.get("@search.score", 0)})

    async with SearchClient(SEARCH_ENDPOINT, INDEX_MANUALS, credential) as client:
        kwargs = {"search_text": query, "top": top}
        if manual_filter:
            kwargs["filter"] = manual_filter
        async for r in await client.search(**kwargs):
            results.append({**r, "_source": "manual", "_score": r.get("@search.score", 0)})

    results.sort(key=lambda r: r["_score"], reverse=True)
    return results[: top * 2]


def format_context(results: list[dict]) -> str:
    """Format search results into a plain-text context string for the LLM prompt."""
    if not results:
        return "No relevant records found in the knowledge base."

    lines = []
    for r in results:
        if r["_source"] == "ticket":
            lines.append(
                f"[Past Repair Ticket] "
                f"Brand: {r.get('appliance_brand', 'Unknown')}, "
                f"Model: {r.get('model_number', 'Unknown')}, "
                f"Issue: {r.get('symptom', '')}, "
                f"Fix: {r.get('fix_summary') or r.get('technician_notes', '')}"
            )
        else:
            source = r.get("source_file", "unknown")
            page = r.get("page_number")
            citation = f"{source}, p.{page}" if page else source
            lines.append(
                f"[Service Manual — {citation}] "
                f"{r.get('brand', '')} {r.get('model_series', '')}: "
                f"{r.get('chunk_text') or r.get('content', '')}"
            )
    return "\n\n".join(lines)


def extract_pdf_citations(results: list[dict]) -> list[dict]:
    """Return unique PDF citations from manual search hits in display order."""
    citations = []
    seen: set[tuple[str, int | None]] = set()

    for r in results:
        if r.get("_source") != "manual":
            continue

        source_file = r.get("source_file", "unknown")
        page_number = r.get("page_number")
        key = (source_file, page_number)
        if key in seen:
            continue
        seen.add(key)

        citations.append(
            {
                "source_file": source_file,
                "page_number": page_number,
                "brand": r.get("brand", ""),
                "model_series": r.get("model_series", ""),
            }
        )

    return citations
