# AGENT — ToolsFactory Service

ToolsFactory catalogs and registers tools. Spec: `Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/openapi.yaml`. Tool lists are corpus‑scoped; registration is idempotent; list formats are stable.

Registering external OpenAPI specs
- Endpoint: `POST /tools/register?corpusId=<id>[&base=<url>]`
- Body: OpenAPI document as JSON; YAML is also accepted. When `base` is present (or `servers[0].url` is set in the document), `http_path` is resolved to an absolute URL using that base.
- Minimal fields used per operation: `operationId` (required), `summary` (optional → name), `description` (optional), HTTP method, and path.
- Helper: `Scripts/openapi/register-teatro-guide-as-tools.sh` fetches the upstream YAML, normalizes to JSON, and registers it with an optional base override.

Unit tests cover registration normalization and corpus filtering. Integration registers the AudioTalk spec and asserts the list contains expected entries. CI builds and tests this package; Studio autostart registers AudioTalk tools during dev.
