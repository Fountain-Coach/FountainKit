# Tools Factory Server Agent

1. **Curated OpenAPI source**
   - This service trusts only operations coming from the FountainAI OpenAPI Curator.
   - After modifying the spec or tool registration, call `POST /curate` with the full list of `file://openapi/...` specs and set `submitToToolsFactory` as needed.

2. **Validation**
   - Run the project’s OpenAPI validation tooling before committing changes.
