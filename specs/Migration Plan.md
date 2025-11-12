# Migration Plan (Authoritative)
## From Multi‑Service OpenAPI Infrastructure to a Unified MIDI‑2.0 Instrument Runtime

---

### 🎯 Objective
Single maintained plan for migrating FountainKit from many OpenAPI services to a single‑host runtime that presents functionality as MIDI‑2.0–defined instruments while retaining full OpenAPI equivalence.

---

### 🧱 Current State — “From”
- Each FountainAI capability runs as an individual **OpenAPI 3.1 service**.
- Communication occurs via HTTP/JSON, with multiple servers, containers, and ports.
- High overhead from:
  - container orchestration
  - inter-service latency
  - redundant serialization
  - duplicated state and logging layers
- Real-time responsiveness limited by HTTP transport.

---

### 🎹 Target State — “To”
A **unified runtime** (the *Fountain Host*) that:
- Loads all former microservices as **local modules or plugins**.
- Exposes them as **midi2 Function Blocks** (Loopback/RTP/BLE; CoreMIDI prohibited) via Capability Inquiry (CI) + Property Exchange (PE).
- Optionally exposes **one consolidated OpenAPI gateway** for external orchestration.
- Provides a single semantic bus for both **real-time** and **declarative** control.

Transport policy alignment (hard rule)
- CoreMIDI is prohibited across the repository.
- Allowed transports: midi2 Loopback (in‑process), RTP MIDI 2.0, and BLE MIDI 2.0 via the `midi2` workspace.

---

### 🔁 Migration Phases

#### Phase 0 – Service‑Minimal bridge (optional but recommended)
- Adopt per‑service targeted builds to keep iteration fast while migrating internals.
- Move OpenAPI generation into each `<service>-service` core; keep thin servers that depend on the core.
- Use wrappers like `Scripts/dev/<service>-min [build|run]` to avoid pulling the full workspace.

#### Phase 1 – Inventory & Classification
- List every existing service and endpoint.
- Label each as:
  - `pure-logic` – stateless compute, safe for in-process migration.
  - `light-state` – minor configuration or persistence (SQLite, files).
  - `external/heavy` – cloud APIs, GPU inference, multi-tenant systems.

#### Phase 2 – Transcode to MIDI-2 Agents
- For `pure-logic` and `light-state` services:
  - Generate MIDI-CI/PE descriptors from OpenAPI specs.
  - Compile endpoints into callable **local functions**.
  - Replace HTTP operations with PE `GetProperty` / `SetProperty` / `Profile-Specific` messages.
- Preserve event semantics:
  - WebSocket/SSE → UMP streams or PE Notify.

Provenance and storage (authoritative)
- Descriptors and facts are persisted in FountainStore, not ad‑hoc files.
- Use a seeder to write under page `agent:<id>` with segment `descriptor.json` (and optional `facts`).
- Applications and the gateway read from FountainStore at runtime and expose a unified descriptor endpoint.

#### Phase 3 – Construct the Fountain Host
- Implement a single runtime that:
  - Loads translated agents as modules.
  - Publishes one midi2 endpoint (Loopback locally; RTP/BLE for network) with multiple Function Blocks. CoreMIDI is not used.
  - Routes internal calls as function invocations (no HTTP).
- Integrate optional gateway for:
  - external API access
  - remote logging
  - security boundaries (OAuth 2 / mTLS)

#### Phase 4 – Consolidate State & Configuration
- Embed shared state into lightweight local stores.
- Map persistent configuration to PE properties.
- Ensure all parameters remain discoverable via CI Inquiry or OpenAPI reflection.

#### Phase 5 – Validation & Parity Testing
- Use conformance tests to verify:
  - identical JSON → PE round-trip behavior
  - timing fidelity:
    - host‑local Loopback: ≤ 5 ms for musical, ≤ 500 ms for config
    - network (RTP/BLE): typical ≤ 25 ms musical, ≤ 750 ms config (document actual SLOs per deployment)
  - schema equivalence and version parity
- Log validation digests and compare against previous builds.

Acceptance criteria (facts → runtime)
- Facts location: Planner/Function Caller/Persist mappings live under FountainStore collection `agent-facts` at id `facts:agent:<agentId>` where `<agentId>` is safe ("/" replaced by "|").
- Mapping format: each property has `id` and `mapsTo.openapi` with `method`, `path`, optional `body: json`.
- Round‑trip: for each property that maps to OpenAPI, a sample JSON payload must:
  - validate against the OpenAPI schema;
  - successfully invoke the HTTP endpoint;
  - be reflected back through a corresponding readable property (or an event) when applicable.
- Observability: Gateway serves `/.well-known/agent-descriptor` and `/.well-known/agent-facts` backed by FountainStore.
- Latency budgets: host‑local loopback requests meet the timing targets above.

#### Phase 6 – Decommission Servers
- Retire standalone containers once:
  - CI/PE descriptors match original OpenAPI definitions.
  - End-to-end tests succeed inside the Host runtime.
- Maintain only one optional **gateway server** for external access if required.

---

### ⚙️ Architectural Outcome
| Layer | Before | After |
|-------|---------|-------|
| Transport | HTTP / JSON | UMP / PE (real-time) + optional HTTP gateway |
| Deployment | Many containers | One runtime process |
| Discovery | OpenAPI registry | MIDI-CI Inquiry |
| Invocation | Network request | In-process call or PE transaction |
| Events | WebSocket | UMP stream / PE Notify |
| State | Distributed | Local embedded DB / PE properties |

---

### 💰 Expected Gains
- **Startup time:** seconds → sub-second  
- **Latency:** < 5 ms intra-module  
- **Resource use:** 60–80 % reduction in CPU/RAM overhead  
- **Operational simplicity:** one process, one log stream  
- **Creative flexibility:** real-time modulation and orchestration through the same protocol

---

### 🚧 Remaining Servers (if any)
- GPU inference or cloud-specific agents  
- External data sources requiring network reachability  
- Public APIs needing OAuth, rate limits, or telemetry isolation  

These remain behind a single thin **Gateway Service** accessed by the Fountain Host.

---

### 📜 Compliance & Versioning
- Contract: `fountain.coach/interoperability/v1`
- Versioning: Semantic Versioning 2.0.0
- Conformance tools:
  - Validate descriptors: `Scripts/tools/agent-validate <descriptor.(yaml|json)>`
  - Seed into FountainStore: `swift run --package-path Packages/FountainApps agent-descriptor-seed <descriptor.(yaml|json)>`
- Drift policy: breaking → major; additive → minor

Where (anchors in repo)
- Descriptor schema: `specs/schemas/agent-descriptor.schema.json:1`
- Human contract: `specs/AGENTS.md:1`
- Validator CLI: `Packages/FountainApps/Sources/agent-validate/main.swift:1` and `Scripts/tools/agent-validate:1`
- Descriptor seeder: `Packages/FountainApps/Sources/agent-descriptor-seed/main.swift:1`
- Gateway descriptor endpoint: `Packages/FountainApps/Sources/gateway-server/GatewayServer.swift:194`

---

### 🪶 Summary

This migration replaces a fleet of networked OpenAPI servers with a **monophonic yet poly-functional host**:  
> a single process where all FountainAI capabilities play together as MIDI-2 instruments,  
> retaining full OpenAPI semantics while eliminating the operational cost of running many servers.

---

Status & Ownership
- This document is the only maintained plan. Keep it current; link it from defining docs (see `specs/AGENTS.md`).
