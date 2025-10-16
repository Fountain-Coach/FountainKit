# ChatKit Gateway Execution Checklist

This checklist translates the recent ChatKit commits and milestone roadmap into executable tasks. Each subtask is framed so it can be checked off after running the associated command or completing the action.

## ✅ Completed (from recent git history)
- [x] `/chatkit/messages` streaming endpoint wired to the LLM gateway (`d34df91` → `88abf97`).
- [x] Attachment upload endpoint implemented with persistence via FountainStore (`cdb5723` → `7378e2d`).
- [x] Milestone roadmap documented (`6ee02a1`).

## 🚀 Next 0–2 days
### 1. LLM Streaming Bridge
- [x] Update `Packages/FountainApps/Sources/gateway-server/openapi/chatkit.yaml` with SSE streaming schema for incremental tokens.
  - Command: `swift run fountain-openapi-curator --lint Packages/FountainApps/Sources/gateway-server/openapi/chatkit.yaml`
- [x] Implement streaming responder that forwards gateway SSE frames to ChatKit in `Packages/FountainApps/Sources/gateway-server/ChatKitGatewayResponder.swift`.
  - Command: `swift build --target gateway-server`
- [x] Extend `ChatKitGatewayTests` with a fake streaming responder asserting incremental framing.
  - Command: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests/testStreamingBridge`

### 2. Attachment Retrieval Endpoint
- [ ] Design `/chatkit/attachments/{id}` in the OpenAPI spec with signed download URL or direct payload.
  - Command: `swift run fountain-openapi-curator --lint Packages/FountainApps/Sources/gateway-server/openapi/chatkit.yaml`
- [ ] Persist attachment metadata (size, MIME, checksum) in FountainStore models within `Packages/FountainApps/Sources/gateway-server/AttachmentStore.swift`.
  - Command: `swift build --target gateway-server`
- [ ] Implement download handler and add tests covering metadata validation.
  - Command: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests/testAttachmentDownload`

## 📅 2–5 days
### 3. Upload Validation
- [ ] Add configuration knobs (`CHATKIT_ATTACHMENT_MAX_MB`, allowed MIME list) in `Packages/FountainApps/Sources/gateway-server/Configuration/ChatKitConfig.swift`.
  - Command: `swift build --target gateway-server`
- [ ] Add negative tests for blocked uploads (`OversizedAttachmentTests`, `InvalidMimeAttachmentTests`).
  - Command: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests/testUploadValidation`

### 4. Corpus Management
- [ ] Implement TTL cleanup worker or manual purge endpoint in `Packages/FountainApps/Sources/gateway-server/AttachmentCleanupJob.swift`.
  - Command: `swift build --target gateway-server`
- [ ] Emit structured logs for uploads/downloads in `Packages/FountainApps/Sources/gateway-server/Logging/ChatKitLogging.swift`.
  - Command: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests/testStructuredLogs`

## 🛠 1–2 weeks
### 5. Message & Thread Persistence
- [ ] Introduce `/chatkit/threads` CRUD spec entries and regenerate clients/servers.
  - Command: `swift run fountain-openapi-curator --lint Packages/FountainApps/Sources/gateway-server/openapi/chatkit.yaml`
- [ ] Persist assistant responses & tool calls in FountainStore models under `Packages/FountainApps/Sources/gateway-server/ThreadStore.swift`.
  - Command: `swift build --target gateway-server`
- [ ] Extend integration tests covering session replay scenarios.
  - Command: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests/testThreadPersistence`

### 6. Tool Call Surfacing
- [ ] Map LLM tool/function calls to ChatKit tool events in `Packages/FountainApps/Sources/gateway-server/ToolCallBridge.swift`.
  - Command: `swift build --target gateway-server`
- [ ] Add tests simulating tool call responses verifying gateway output.
  - Command: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests/testToolCallSurfacing`

## 📚 Documentation & Ops
- [ ] Update `Packages/FountainApps/Sources/gateway-server/README.md` with attachment workflow & LLM streaming notes.
  - Command: `open Packages/FountainApps/Sources/gateway-server/README.md`
- [ ] Document configuration knobs in `Docs/operations/chatkit_gateway.md`.
  - Command: `open Docs/operations/chatkit_gateway.md`
- [ ] Draft runbook for clearing attachment corpus and regenerating signed URLs in `Workspace/runbooks/chatkit_attachment_reset.md`.
  - Command: `open Workspace/runbooks/chatkit_attachment_reset.md`

## 🔍 Validation
- [ ] Ensure CI runs focused tests: `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests` on macOS/Linux.
  - Command: `Scripts/ci-smoke.sh --suite chatkit`
- [ ] Add integration smoke test bootstrapping `gateway-server`, uploading fixture, retrieving download.
  - Command: `Scripts/ci-smoke.sh --suite chatkit-download`

Check off each item as milestones land to maintain alignment between implementation work and the roadmap.
