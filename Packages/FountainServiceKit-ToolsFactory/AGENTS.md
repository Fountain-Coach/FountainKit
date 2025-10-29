# AGENT — ToolsFactory Service

What: ToolsFactory catalogs and registers tools (OpenAPI operations). Spec: `Packages/FountainServiceKit-ToolsFactory/Sources/ToolsFactoryService/openapi.yaml`. Lists are corpus‑scoped; registration is idempotent; list formats are stable.

Register external OpenAPI
- Endpoint: `POST /tools/register?corpusId=<id>[&base=<url>]`
- Body: OpenAPI document as JSON (YAML accepted). If `base` is present (or `servers[0].url` exists), resolve `http_path` to an absolute URL using that base.
- Minimal per operation: `operationId` (required), `summary` (optional → name), `description` (optional), HTTP method, path.
- Helper: `Scripts/openapi/register-teatro-guide-as-tools.sh` normalizes upstream YAML to JSON and registers it (optional base override).

Build/test
- Build: `swift build --package-path Packages/FountainServiceKit-ToolsFactory -c debug`
- Tests: `swift test --package-path Packages/FountainServiceKit-ToolsFactory -c debug`

Testing
Unit covers registration normalization and corpus filtering. Integration registers AudioTalk and asserts expected entries. CI builds/tests this package; Studio autostart registers AudioTalk tools during dev.
