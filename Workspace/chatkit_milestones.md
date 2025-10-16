# ChatKit Gateway Integration – Upcoming Milestones

This roadmap keeps the ChatKit ↔ FountainKit workstream focused. Each milestone should land with specs, generator configs, tests, and documentation updates.

## 🚀 Next 0–2 days
- **LLM Streaming Bridge**
  - Replace the stub ChatResponder with a streaming bridge that listens to token SSE from the LLM gateway and forwards tokens to ChatKit.
  - Extend `ChatKitGatewayTests` with a fake streaming responder to assert incremental SSE framing.
- **Attachment Retrieval Endpoint**
  - Design `/chatkit/attachments/{id}` in the spec; expose a signed download URL or direct response from the gateway.
  - Persist attachment metadata (size, MIME, checksum) and return it in the download response.

## 📅 2–5 days
- **Upload Validation**
  - Enforce size & MIME limits via configuration (`CHATKIT_ATTACHMENT_MAX_MB`, allowed MIME list).
  - Add tests for oversized/blocked attachments; confirm FountainStore rejects or flags invalid payloads.
- **Corpus Management**
  - Add background cleanup (TTL-based or manual purge endpoint) for expired attachments.
  - Emit structured logs for uploads & downloads (session id, attachment id, size).

## 🛠 1–2 weeks
- **Message & Thread Persistence**
  - Introduce `/chatkit/threads` (list/create/delete) powered by FountainStore.
  - Store assistant responses & tool calls, enabling session replay and long-term memory.
- **Tool Call Surfacing**
  - Map LLM function calls to ChatKit tool events; expose matching OpenAPI schema.
  - Build tests that simulate function call responses and verify gateway output.

## 📚 Documentation & Ops
- Update `Packages/FountainApps/Sources/gateway-server/README.md` with attachment workflow & LLM streaming notes.
- Document configuration knobs (`CHATKIT_DEFAULT_MODEL`, `CHATKIT_UPLOAD_ROOT`, TTL values) in operational playbooks.
- Add a runbook for clearing Attachment corpus and regenerating signed URLs.

## 🔍 Validation
- Expand CI to run `swift test --package-path Packages/FountainApps --filter ChatKitGatewayTests` on both macOS and Linux.
- Add integration smoke test that boots `gateway-server`, uploads a fixture, and retrieves it via the new download endpoint.

Keep this file updated after each milestone lands to maintain a single source of truth for ChatKit integration status.
