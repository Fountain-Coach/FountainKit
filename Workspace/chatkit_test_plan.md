# ChatKit Gateway Test Plan

This document describes the automated test suite we will build while wiring the FountainKit gateway to the ChatKit-JS contract. The goal is to codify the behaviour promised in the “Integrating ChatKit-JS into FountainKit Gateway and Publishing Frontend” guide so that the gateway can be developed with TDD and regain green status automatically (“self-healing”) whenever regressions are introduced.

## Guiding Principles
- **Contract first**: mirror the request/response shapes (and error semantics) that ChatKit expects for session bootstrap, message dispatch, streaming, uploads, and thread management.
- **Deterministic & fast**: rely on in-process stubs instead of remote services; keep tests under a few seconds so they can run in CI and locally on every change.
- **Layered coverage**: mix narrow unit tests (for auth/token and state helpers) with integration tests that exercise the Gateway HTTP surface end-to-end using the existing `ServerTestUtils`.
- **Observable outputs**: assert on bodies, headers, and SSE framing so that the suite catches both functional bugs and compatibility drift.

## Test Matrix

| Area | Focus | Coverage Style | Key Assertions |
|------|-------|----------------|----------------|
| **Token lifecycle** | `/api/chatkit/start` & `/api/chatkit/refresh` | Unit + HTTP integration | 201/200 status codes, JSON `{client_secret, expires_at}`, secret signed / stored once, refresh invalidates previous, handles expired/unknown ids with 401 |
| **Message dispatch** | `/api/chatkit/message` (or `/events`) bridging to LLM pipeline | Integration (HTTP) + stubbed backend | Valid session required, request payload forwarded to `GatewayChatClient`, SSE stream produced, final chunk contains assistant answer & metadata |
| **Streaming** | SSE channel semantics | Integration | `Content-Type: text/event-stream`, `data:` frames flush tokens, `[DONE]` terminator, reconnect after refresh |
| **Attachments** | `/api/chatkit/upload` workflow | Integration + filesystem sandbox | Multipart upload accepted, metadata persisted (likely via `FountainStoreClient` stub), gateway returns attachment id + signed URL |
| **Thread history** | thread creation/listing APIs (if exposed) | Unit + integration | New session -> new thread id, `GET /api/chatkit/threads` lists stored transcripts, invalid thread id -> 404 |
| **Publishing frontend** | Static asset hosting | Integration (filesystem) | Gateway serves `Public/index.html` containing `<openai-chatkit>`, `chatkit.js` script served with `application/javascript`, caching headers set |
| **Security & rate limits** | Auth, CORS, flood control | Unit + integration | Missing bearer -> 401, invalid signature -> 403, rate limiter kicks in after N requests/min, CORS headers present on preflight |
| **Error surfaces** | Failure transparency | Integration | Backend failure -> `chatkit.error` SSE event, JSON error body includes `error.code` & human message |

## Test Targets & Tooling

1. **`GatewayServerTests` (XCTest)**  
   - Extend existing target in `Packages/FountainApps/Tests/GatewayServerTests`.  
   - Add new file `ChatKitGatewayTests.swift` co-located with current tests for clarity.
   - Reuse `ServerTestUtils.startGateway` but override gateway plugins to mount the ChatKit plugin with deterministic stubs (see below).

2. **Supporting Test Utilities**
   - **Stub session store**: in-memory store that exposes inspection hooks (active sessions, expiry times, revoked tokens).  
   - **Stub chat backend**: conformer that replaces `GatewayChatClient` / LLM pipeline, returning scripted SSE frames or JSON payloads.  
   - **SSE client helper**: async sequence wrapper around `URLSession.dataTask` producing parsed events for concise assertions.
   - **Multipart builder**: helper to craft upload payloads without hitting disk.

3. **Fixtures**
   - Sample ChatKit transcript payload saved in `Tests/Fixtures/chatkit-message.json`.  
   - Minimal `index.html` fixture verifying `<openai-chatkit>` presence.  
   - Upload sample (PNG bytes) generated on the fly to avoid binary fixtures.

## Planned Test Cases

### Token Lifecycle
1. **`testStartSessionGeneratesOpaqueSecret`**  
   - Arrange: POST `/api/chatkit/start` without Authorization (if public) or with API key.  
   - Assert: 201, JSON schema matches expectations, secret persisted in store, TTL within configured bounds.
2. **`testRefreshSessionRotatesSecret`**  
   - Call `/refresh` with existing secret. Ensure new secret differs; old secret rejected afterwards.
3. **`testRefreshWithExpiredSecretReturns401`**  
   - Expire secret via stub; expect 401 and structured error body.

### Messaging & Streaming
4. **`testPostMessageInvokesLLMBackend`**  
   - Provide session secret, send message array. Stub backend records payload; SSE stream returns tokens `["Hello", " world"]`. Assert final aggregated answer.
5. **`testStreamingFramingMatchesSpec`**  
   - Collect SSE events, assert each is `data: {json}\n\n`, final event `[DONE]`.  
   - Validate metadata (model, provider, citations).
6. **`testUnauthorizedMessageReturns401`**  
   - No secret header -> 401 with error JSON.

### Uploads
7. **`testAttachmentUploadStoresFile`**  
   - POST multipart with session secret and file. Stub store returns id `att-1`. Assert response, ensure bytes captured.
8. **`testUploadRejectsUnsupportedMimeType`**  
   - Ingest `.exe` -> 415.

### Thread Management
9. **`testListThreadsIncludesCurrentSession`**  
   - After sending messages, GET `/api/chatkit/threads` -> contains thread id with last message summary.
10. **`testDeleteThreadRevokesSession`**  
   - DELETE thread -> future events using same secret fail.

### Publishing Frontend
11. **`testPublishingFrontendServesChatKitIndex`** ✅  
   - Boot `PublishingFrontendPlugin` against real `Public/` assets; assert `/` returns HTML pointing at `chatkit.js`.  
12. **`testChatKitScriptServedWithCorrectMime`** ✅  
   - Request `/chatkit.js`; assert `application/javascript` and bootstrap guard present.

### Security & Observability
13. **`testCorsPreflightHandled`**  
   - OPTIONS request -> 204 with `Access-Control-Allow-Origin`.
14. **`testRateLimitExceeded`**  
   - Configure low limit in test; hammer endpoint; expect 429 & SSE `error` event.
15. **`testStructuredLogsContainChatKitFields`**  
   - Capture stderr log line, ensure `evt=chatkit_request` fields present.

### Regression Guards
16. **`testOpenApiDocumentIncludesChatKitPaths`**  
   - Load `openapi.yaml`, assert `/api/chatkit/*` paths exist so generator covers them.
17. **`testGatewayConfigEnablesChatKitPluginByDefault`**  
   - Initialize server; check plugin chain for ChatKit plugin to prevent accidental removal.

## TDD Workflow
1. Write failing test for each contract item (e.g. start session).  
2. Implement minimal gateway code to pass test (new plugin, handlers, stubs).  
3. Run `swift test --package-path Packages/FountainApps` continuously; gate successive changes on green runs.  
4. Once the HTTP contract is green, expand coverage to negative cases and SSE framing.  
5. Wire suite into CI (`swift test --package-path Packages/FountainApps --filter ChatKit`) after implementation lands.

## Self-Healing Hooks
- Guard rails around config: tests fail fast when env variables missing, enabling automatic diagnosis.
- SSE helper asserts on timing and reconnects; if network stack regresses, suite pinpoints it.
- Logging test ensures observability fields remain intact for runtime self-healing dashboards.

## Next Steps
1. Scaffold stub components and SSE helper in the test target.
2. Land initial token lifecycle tests, then iterate through matrix row-by-row.
3. Update CI matrix to include the new filter so ChatKit coverage runs alongside existing gateway tests.
4. Document the test suite in `Packages/FountainApps/Sources/gateway-server/README.md` so contributors know how to execute and extend it.

With this suite in place, we can comfortably practice TDD for the remaining gateway work and rely on CI to detect and heal regressions that might otherwise break the ChatKit experience.
