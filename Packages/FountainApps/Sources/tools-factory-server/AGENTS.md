# Tools Factory Server — Agent Guide

This executable hosts the ToolsFactory service. Operations must come from the FountainAI OpenAPI Curator — treat curated specs as the only source of truth. After changing a spec or tool registration, call `POST /curate` with the full list of `file://openapi/...` documents and set `submitToToolsFactory` as needed.

Run the project’s OpenAPI validation tooling before committing to keep CI green. Keep this server thin: wiring, transport, env handling, and readiness endpoints; the service kit holds the spec and handlers.
