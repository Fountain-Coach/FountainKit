# FountainAI ↔ Fountain Gateway Decoupling Plan

Goal: decouple “FountainAI” (apps/libs that chat, seed, render) from “Fountain Gateway” (server + plugins) so each evolves, runs, and fails independently while inter‑operating via clear contracts and OpenAPI. Engraver Studio must always be able to chat reliably with a direct provider; Gateway remains optional.

Important: we do not require (nor encourage) logging into any commercial LLM vendor to use the system. The first‑class/default configuration is a locally hosted, open‑source LLM runtime (e.g., llama.cpp/ollama/vLLM/text‑gen‑webui). The reason we mirror OpenAI’s request/response shapes is adapter compatibility — not vendor lock‑in. If an API key is present we can optionally talk to a hosted provider for parity testing, but it is not a prerequisite for any core flow.

## Guiding Principles
- Clear contracts, no reach‑through; clients talk only to contracts, servers expose only OpenAPI.
- Gateway is optional; apps must run with a direct provider without any gateway.
- No vendor login: the default provider is a local OSS LLM runtime. Hosted providers are optional adapters.
- Policy by dialogue (personas), not static toggles.
- OpenAPI‑first at package seams; generated code in APIClients only.
- Fail soft: Gateway/policies must never block basic chat.

## Target SPM Workspace
- **FountainCore**
  - Contracts: `ChatStreaming`, `ChatMessage/Request/History`, `ProviderError`, `TelemetryEvent`, `PolicyDecision` (DTOs only).
  - Zero dependency on GatewayKit, providers, or UI.
- **FountainAIKit (new)**
  - Engraver chat ViewModel and helpers; depends on FountainCore + Provider facades.
  - No Gateway imports; no boot/env control.
- **Providers (new, small)**
  - `Provider-LocalLLM` (default; local engine via simple HTTP or native bindings), `Provider-OpenAI` (compat adapter), `Provider-Anthropic` (compat adapter, stub initially), `Provider-Gateway` (wraps `FountainAPIClients/LLMGatewayAPI`).
  - Providers are swappable; none of them is required to be a vendor login — the local provider is first‑class.
- **FountainAPIClients** (existing)
  - Generated OpenAPI clients; no app logic.
- **FountainGatewayKit** (server only)
  - Gateway server + plugins (rate‑limiter, auth, personas, policy). No dependency back to AIKit.
- **FountainDevHarness (new)**
  - EnvironmentManager + dev up/down orchestration (optional utility for apps/console).
- **EngraverStudio (app)**
  - Depends on FountainAIKit (+ optionally DevHarness); default transport = Provider‑OpenAI.
  - Gateway UI/controls not present by default; added only as optional extension.
- **GatewayConsole (new app)**
  - Dedicated UI for Gateway (Traffic, Routes, Policies, Personas, Auth, Metrics). Talks via OpenAPI only.

## Phased Refactor
**Phase 0 — Stop the bleed (1–2 days)**
- Default Studio to Provider‑LocalLLM; hide Gateway UI in direct mode.
- Add OpenAI adapter only as a convenience (if an API key exists) — not required.
- Acceptance: fresh checkout + local LLM runtime reachable on `http://127.0.0.1:<port>` → chat in <30s with zero logins.

**Phase 1 — Define core contracts (1–2 days)**
- FountainCore: `ChatStreaming`, message/history DTOs, `ProviderError`, `TelemetryEvent`, `PolicyDecision`.
- Acceptance: Providers compile against FountainCore only.

**Phase 2 — Lift ViewModel into FountainAIKit (2–3 days)**
- Create FountainAIKit; move Engraver ViewModel + helpers from EngraverChatCore.
- Acceptance: Studio builds/runs with AIKit + Provider‑OpenAI; no Gateway imports.

**Phase 3 — Providers (2–4 days)**
- Provider‑LocalLLM (SSE+final, or final only depending on engine), Provider‑Gateway (wraps generated client), Provider‑OpenAI (compat), Provider‑Anthropic (compat stub).
- Provider select via `ENGRAVER_PROVIDER=local|gateway|openai|anthropic` with `local` as default.
- Acceptance: swap provider via env; Studio chat unaffected; local provider requires no credentials.

**Phase 4 — Decouple Gateway UI (3–5 days)**
- Move EnvironmentManager to DevHarness; create GatewayConsole app; remove Gateway controls from Studio by default.
- Acceptance: Studio ships lean; GatewayConsole manages Gateway fully.

**Phase 5 — Policy Persona (server) scaffold (5–8 days)**
- `PolicyGatewayPlugin`: `prepare(request)` consults Policy Persona (via ChatKit) → `PolicyDecision` (allow/throttle/block/challenge). RateLimiter becomes data source only.
- Acceptance: policy mode enabled → persona adjudicates requests.

**Phase 6 — Client insight (2–3 days)**
- Optional Studio pane: last policy decision transcript when Gateway used. Hidden in direct mode.

**Phase 7 — CI/Release (2–3 days)**
- Matrix build/tests per package; lint OpenAPI; no generated code committed.

## Migration Details
- App path removes Gateway imports; Provider‑Gateway becomes pure transport.
- Bootstrap/Awareness remain optional via OpenAPI clients (no GatewayKit imports in Studio path).
- Environment boot moves behind DevHarness.
- Rate‑limit toggles live in GatewayConsole only.

## Success Criteria
- Studio always chats with a local OSS LLM provider out of the box; no vendor login required.
- Providers (local/gateway/hosted) swap via env only; Studio code unchanged.
- Gateway failure never blocks Studio chat.

## Risks & Mitigations
- Cross‑package breakage → keep FountainCore minimal and stable; shims where needed.
- UI scope creep → GatewayConsole separate; Studio stays lean.
- Policy complexity → ship allow‑all MVP, add throttling/challenge next.

## Deliverables (PRs)
- PR1: Default Provider‑OpenAI in Studio; hide Gateway panes in direct mode; direct client hardening.
- PR2: FountainCore contracts + FountainAIKit; move ViewModel; remove Gateway imports from app path.
- PR3: Provider‑OpenAI/Gateway/Anthropic; env‑based provider select.
- PR4: FountainDevHarness extraction; Studio compiles without it.
- PR5: GatewayConsole app; remove Gateway UI from Studio.
- PR6: PolicyGatewayPlugin skeleton; allow‑all; persona hooks.
- PR7: Optional policy viewer in Studio; CI matrix.
