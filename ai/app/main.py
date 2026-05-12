"""
FastAPI backend for the Appliance AI technician chat app.

Endpoints:
  GET  /         — serves the chat UI (HTML)
  GET  /health   — liveness probe for Container Apps
  POST /chat     — search indexes + stream gpt-4o response (SSE)

Credential pattern (from Azure-Samples/get-started-with-ai-chat):
  - Local: AzureDeveloperCliCredential (az login / azd auth login)
  - Production: ManagedIdentityCredential with UAMI client_id (AZURE_CLIENT_ID env var)

SSE stream format:
  data: {"content": "...", "type": "message"}\\n\\n
  data: {"type": "stream_end"}\\n\\n
"""

import os
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, HTMLResponse
from pydantic import BaseModel

from azure.ai.inference.aio import ChatCompletionsClient

from chat import get_credential, stream_chat
from search import search_both_indexes, format_context

STATIC_DIR = Path(__file__).parent / "static"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create long-lived SDK clients once at startup and clean up on shutdown."""
    credential = get_credential()
    chat_client = ChatCompletionsClient(
        endpoint=os.environ["AZURE_INFERENCE_ENDPOINT"],
        credential=credential,
        # Scope for Azure AI Services (covers both classic and MaaS endpoints)
        credential_scopes=["https://cognitiveservices.azure.com/.default"],
    )
    app.state.credential = credential
    app.state.chat_client = chat_client
    yield
    await chat_client.close()
    await credential.close()


app = FastAPI(title="Appliance AI Chat", docs_url=None, redoc_url=None, lifespan=lifespan)


class ChatRequest(BaseModel):
    message: str
    brand: str = ""
    model_number: str = ""


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
async def index():
    """Serve the chat UI."""
    return HTMLResponse((STATIC_DIR / "index.html").read_text())


@app.post("/chat")
async def chat(req: ChatRequest, request: Request):
    """
    Search both knowledge indexes, build context, and stream an SSE gpt-4o response.
    The user identity is available from the X-Ms-Client-Principal-Name header
    when running behind Container Apps Easy Auth.
    """
    results = await search_both_indexes(
        req.message,
        request.app.state.credential,
        brand=req.brand,
    )
    context = format_context(results)

    return StreamingResponse(
        stream_chat(request.app.state.chat_client, req.message, context),
        media_type="text/event-stream",
        headers={"X-Accel-Buffering": "no"},  # disable nginx/proxy buffering
    )
