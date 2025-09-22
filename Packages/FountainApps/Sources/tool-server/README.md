# Tool Server

The Tool Server executable exposes the curated Tool invocation API over HTTP. It delegates request handling to `ToolServerService` from `FountainServiceKit-ToolServer` and adds lightweight health and metrics endpoints for orchestration.

## OpenAPI specification

- Tool Server API: [`Packages/FountainSpecCuration/openapi/v1/tool-server.yml`](../../../FountainSpecCuration/openapi/v1/tool-server.yml)

## Endpoints

- `/_health` – JSON health probe used by dev tooling and orchestrators.
- `/metrics` – Prometheus-style scrape for service liveness.
- All other routes are defined in the OpenAPI document and handled by `ToolServerService`.

## Running locally

```bash
swift run --package-path Packages/FountainApps tool-server
```

Set `PORT` to override the default `8012` listener.
