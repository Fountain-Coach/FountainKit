# Gateway Server

The Gateway server is the control-plane entry point that authenticates requests, enforces policy, orchestrates LLM personas, and routes traffic to downstream Fountain services. The executable composes plugins from `FountainGatewayKit` with publishing and role-guard utilities so the binary can be launched directly via `swift run`.

## OpenAPI specifications

- Gateway surface: [`Packages/FountainSpecCuration/openapi/v1/gateway.yml`](../../../FountainSpecCuration/openapi/v1/gateway.yml)
- Core plugins:
  - Auth gateway: [`Packages/FountainSpecCuration/openapi/v1/auth-gateway.yml`](../../../FountainSpecCuration/openapi/v1/auth-gateway.yml)
  - ChatKit gateway: [`Packages/FountainSpecCuration/openapi/v1/chatkit-gateway.yml`](../../../FountainSpecCuration/openapi/v1/chatkit-gateway.yml)
  - Curator gateway: [`Packages/FountainSpecCuration/openapi/v1/curator-gateway.yml`](../../../FountainSpecCuration/openapi/v1/curator-gateway.yml)
  - LLM gateway: [`Packages/FountainSpecCuration/openapi/v1/llm-gateway.yml`](../../../FountainSpecCuration/openapi/v1/llm-gateway.yml)
  - Rate limiter gateway: [`Packages/FountainSpecCuration/openapi/v1/rate-limiter-gateway.yml`](../../../FountainSpecCuration/openapi/v1/rate-limiter-gateway.yml)
  - Role health check gateway: [`Packages/FountainSpecCuration/openapi/v1/role-health-check-gateway.yml`](../../../FountainSpecCuration/openapi/v1/role-health-check-gateway.yml)
  - Payload inspection gateway: [`Packages/FountainSpecCuration/openapi/v1/payload-inspection-gateway.yml`](../../../FountainSpecCuration/openapi/v1/payload-inspection-gateway.yml)
  - Budget breaker gateway: [`Packages/FountainSpecCuration/openapi/v1/budget-breaker-gateway.yml`](../../../FountainSpecCuration/openapi/v1/budget-breaker-gateway.yml)
  - Destructive guardian gateway: [`Packages/FountainSpecCuration/openapi/v1/destructive-guardian-gateway.yml`](../../../FountainSpecCuration/openapi/v1/destructive-guardian-gateway.yml)
  - Security sentinel gateway: [`Packages/FountainSpecCuration/openapi/v1/security-sentinel-gateway.yml`](../../../FountainSpecCuration/openapi/v1/security-sentinel-gateway.yml)

These specs describe every HTTP contract the server exposes or invokes, replacing the legacy `openapi/` tree.

## Key responsibilities

- Load persona orchestration, publishing frontend assets, and rate limiting configuration from the environment or configuration store.
- Wire gateway plugins (auth, ChatKit, curation, LLM, policy enforcement) together into a single `GatewayServer` instance.
- Expose optional DNS emulation when launched with `--dns` for local testing.

## ChatKit workflows

### Attachment lifecycle

- Uploads are buffered through `ChatKitGatewayPlugin`, which persists binary blobs inside the `chatkit` corpus (`attachments` collection) managed by `ChatKitUploadStore` and parallel metadata records in `GatewayAttachmentStore` (`attachment-metadata` collection).
- After each successful upload the gateway emits a structured JSON log via `ChatKitLogging` including request identifiers, checksum, MIME type, and byte size so that ingestion can be audited downstream.
- Retention is enforced by `AttachmentCleanupJob`, which scans the corpus chronologically and prunes expired attachments based on the configured TTL, deleting both the blob and metadata entries when a record ages out.

### LLM streaming bridge

- `ChatKitGatewayResponder` proxies `/chatkit/messages` requests to the LLM gateway using `ChatRequest` payloads and prefers `text/event-stream` responses when the client asks for streaming.
- The responder decodes incremental SSE frames, emitting `delta` events for partial tokens and forwarding final usage metadata and tool-call envelopes so ChatKit sessions receive the same timeline a direct LLM client would observe.
- When a non-streaming response is returned, the responder falls back to the JSON contract, extracting the `answer`, provider/model hints, token usage, and any surfaced tool calls before replying to the ChatKit client.

### Publishing frontend

- Static assets under `Public/` ship a ChatKit-JS shell (`index.html`, `chatkit.js`, `styles.css`). The bootstrap file requests `/chatkit/session` and mounts the ChatKit widget once `window.ChatKit` is available from the CDN.
- Regression tests (`ChatKitGatewayTests/testPublishingFrontendServesChatKitIndex`, `ChatKitGatewayTests/testChatKitScriptServedWithCorrectMime`) ensure the publishing plugin keeps serving the expected HTML and JavaScript MIME types.
- Upstream sources for the widget live in the `Workspace/deps/chatkit-js` submodule; update it regularly (`git submodule update --remote Workspace/deps/chatkit-js`) before refreshing the static bundle.
- A ready-to-run plain web demo lives in `Workspace/demos/chatkit-web`; launch it with `./Workspace/demos/chatkit-web/run-demo.sh` for a one-command gateway + static server setup (or host manually if preferred).
- Set `window.chatkitConfig.auto = false` when importing `Public/chatkit.js` from custom pages to opt out of automatic bootstrap and drive the session flow yourself.

## Related packages

- `FountainGatewayKit`: shared gateway plugins, orchestrator, and utilities referenced by this executable.
- `PublishingFrontend`: static asset host embedded via `PublishingFrontendPlugin`.
- `FountainSpecCuration`: authoritative OpenAPI specifications listed above.
