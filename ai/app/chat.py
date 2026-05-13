"""
Chat wrapper using the azure-ai-inference SDK (ChatCompletionsClient).

Emits SSE-compatible JSON events matching the reference pattern from
Azure-Samples/get-started-with-ai-chat:
  data: {"content": "...", "type": "message"}\\n\\n
  data: {"type": "stream_end"}\\n\\n
"""

import os
import json
from typing import AsyncGenerator

from azure.ai.inference.aio import ChatCompletionsClient
from azure.ai.inference.models import SystemMessage, UserMessage
from azure.identity.aio import AzureDeveloperCliCredential, ManagedIdentityCredential

INFERENCE_ENDPOINT = os.environ.get("AZURE_INFERENCE_ENDPOINT", "")
CHAT_DEPLOYMENT = os.environ.get("AZURE_AI_CHAT_DEPLOYMENT_NAME", "gpt-4o")
TENANT_ID = os.environ.get("AZURE_TENANT_ID", "1ed2126d-597d-465e-b5df-95e96c61399f")

SYSTEM_PROMPT = """You are an expert appliance repair assistant helping technicians in the field.

Use the provided context from service manuals and past repair tickets to answer the question.
- If context is relevant, reference it (e.g., "Based on a past ticket..." or "The service manual says...")
- When you use a service-manual fact, add an inline citation immediately after the claim in the form [source_file p.X].
- Only cite facts that are present in the provided context, and prefer the most specific PDF/page available.
- If context is not relevant or missing, say so and give your best general guidance
- Be concise and practical — the technician may be at a job site on their phone
- Focus on actionable steps, part numbers, and common fixes"""


def get_credential(client_id: str | None = None):
    """
    Return the appropriate credential for the current environment.
    - Production (RUNNING_IN_PRODUCTION=true): ManagedIdentityCredential using the UAMI client_id
    - Local dev: tries AzureCliCredential (az login) first, then AzureDeveloperCliCredential (azd auth login)
    """
    if os.getenv("RUNNING_IN_PRODUCTION"):
        return ManagedIdentityCredential(client_id=client_id or os.getenv("AZURE_CLIENT_ID"))
    # Try az CLI first (common for local dev without azd installed)
    try:
        from azure.identity.aio import AzureCliCredential
        return AzureCliCredential(tenant_id=TENANT_ID)
    except Exception:
        return AzureDeveloperCliCredential(tenant_id=TENANT_ID)


async def stream_chat(
    chat_client: ChatCompletionsClient,
    user_message: str,
    context: str,
    citations: list[dict] | None = None,
) -> AsyncGenerator[str, None]:
    """
    Stream a chat response given the user question and search context.
    Yields SSE-formatted data lines for the frontend EventSource / fetch reader.
    """
    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        UserMessage(
            content=(
                f"Context from knowledge base:\n{context}\n\n"
                f"Technician question: {user_message}\n\n"
                "If you use any service-manual details, include inline citations like [manual.pdf p.3]."
            )
        ),
    ]

    response = await chat_client.complete(
        model=CHAT_DEPLOYMENT,
        messages=messages,
        stream=True,
        max_tokens=800,
        temperature=0.3,
    )

    async for update in response:
        if update.choices and update.choices[0].delta.content:
            yield f"data: {json.dumps({'content': update.choices[0].delta.content, 'type': 'message'})}\n\n"

    if citations:
        yield f"data: {json.dumps({'type': 'citations', 'items': citations})}\n\n"

    yield f"data: {json.dumps({'type': 'stream_end'})}\n\n"
