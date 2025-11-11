# AGENTS.md  
## FountainAI Interoperability Contract between OpenAPI Microservices and MIDI 2.0 Instruments  

> Specification Version: 1.0.0  
> Applies to: FountainAI Agent Ecosystem (MIDI ↔ OpenAPI Interoperability)  
> Status: Draft for implementation feedback

---

##  Purpose

This document defines the **interoperability contract** governing how **OpenAPI 3.1–defined microservices** and **MIDI 2.0–defined instruments** coexist, communicate, and compose inside the **FountainAI agent ecosystem**.  

It provides a shared ontology, transport, and capability model enabling agents—whether embodied in hardware, code, or LLMs—to act as peers on one semantic bus.

The goal is simple:

> **Every capability, whether exposed by a RESTful API or a physical instrument, must be discoverable, callable, and composable within the same reasoning graph.**

---

## Conceptual Model

| Layer | Description | Example Entities |
|-------|--------------|------------------|
| **Capability Layer** | Declares what an agent *can do* via OpenAPI 3.1 or MIDI-CI/PE descriptors. | `generateSound`, `analyzeDrift`, `registerCorpus` |
| **Interoperability Layer** | Translates between HTTP semantics and MIDI-2.0 semantics. | `openapi-to-midi` and `midi-to-openapi` composers |
| **Ensemble Layer** | Coordinates agents into temporal and semantic structures (ensembles). | `baseline-awareness-service`, `midi-bridge-daemon`, `planner-service` |
| **Cognitive Layer** | LLM orchestration; interprets schemas and profiles as reasoning primitives. | `Codex`, `Planner`, `Orchestrator` |

---

## Agent Identity

Every FountainAI agent—hardware or software—MUST advertise a minimal identity block:

```yaml
x-agent-id: "fountain.ai/agent/{namespace}/{name}"
x-agent-kind: "microservice" | "instrument"
x-agent-version: "semver"
x-agent-capabilities: ["capabilityId", "..."]
x-agent-protocol: "openapi-3.1" | "midi-ci-pe" | "hybrid"
```

Resolution
	•	Microservices use their OpenAPI info block + x-agent-* extensions.
	•	Instruments use MIDI-CI identity replies + PropertyExchange descriptors.
	•	Bridges normalize both into a shared AgentDescriptor JSON.

---

## Capability Declaration

Capabilities are typed functions expressed in either domain:

| Aspect | OpenAPI Mapping | MIDI 2.0 Mapping |
|--------|------------------|------------------|
| **Schema** | `components/schemas/*` | `PropertyExchange` descriptors |
| **Invocation** | `paths/*` (HTTP operations) | `SetProperty`, `Profile-Specific` messages |
| **Events** | `websocket` / `SSE` | `UMP Stream` or `PE Notify` |
| **Constraints** | JSON Schema keywords | PE constraints (range, enum, pattern) |
| **Introspection** | `/openapi.json` | `CI Inquiry` |

Agents MUST preserve these constraints when transcoding.

--- 

## Interoperability Rules

#### Hard Rules (Mandatory)

**Schema Equivalence**  
Each OpenAPI schema exposed through MIDI 2.0 Property Exchange must remain type-consistent and round-trippable.

**Transport Separation**  
- Real-time control → MIDI 2.0 UMP or PE Notify  
- Declarative configuration → HTTP / JSON  

**Time Fidelity**  
When converting HTTP actions to MIDI streams, timestamps and group / channel context **must** be preserved as metadata.

**Self-Description**  
Every agent must respond to `GET /.well-known/agent-descriptor` (OpenAPI form) or `CI Inquiry` (MIDI form), returning identical metadata.

**Version Drift Detection**  
On schema changes, bridges emit a `ProfileChanged` or `x-agent-version.bump` event to trigger re-composition.

---

### Transport Policy (Hard Rule)

- CoreMIDI is prohibited across the repository for concurrency, determinism, CI portability, and Linux compatibility reasons. Do not import or depend on CoreMIDI.  
- Allowed transports for agent interoperability and audition:  
  - Loopback (in‑process) via midi2 Loopback transport  
  - RTP MIDI 2.0 via the `midi2` workspace  
  - BLE MIDI 2.0 via the `midi2` workspace  
- Defaults must not rely on CoreMIDI. When referring to “virtual instruments/endpoints,” read as midi2 Loopback/RTP/BLE constructs only.

#### Soft Rules (Defaults)

- Default endpoint roots: `/properties`, `/perform`, `/events`, `/profiles`  
- Default MIDI 2.0 group assignment follows OpenAPI tag ordering.  
- If units are unspecified, default to `x-unit: none`.

#### Validation Rules

- JSON ⇄ PE schema validation must pass pre-flight tests before publication.  
- Round-trip test vectors (sample payloads) are required in CI.  
- Bridges must log schema-hash digests for traceability.

#### Correction Logic

When translation ambiguity occurs:  
- Missing `minimum` / `maximum` → infer from unit or MIDI norm.  
- Ambiguous `oneOf` / `anyOf` → flatten with explicit discriminator.  
- Unknown PE type → fallback to `binary` + `x-unknown:true`.

--- 

## Event and Stream Semantics

Domain	Transport	Encoding
HTTP Events	SSE / WebSocket	JSON schema-validated
MIDI Events	UMP Stream	JSON-mapped UMP frame

Bridges must support both push (HTTP → MIDI) and pull (MIDI → HTTP) directions with latency ≤ 5 ms for musical channels and ≤ 500 ms for configuration channels.

---

## Agent Composition

### Discovery

Agents publish themselves into the Registry Service, which indexes:
	•	capability signatures
	•	schema hashes
	•	event types
	•	protocol bindings

### Linking

The Planner Service composes agents by matching output schema A → input schema B or Profile A → FunctionBlock B.
Link definitions are stored as CompositionGraph documents (YAML).

### Execution

During runtime:
	•	Continuous links stream UMP data or WebSocket JSON frames.
	•	Discrete links trigger HTTP or PE transactions.
	•	State convergence monitored via baseline-awareness-service.

--- 

## LLM Orchestration Layer

Large-language-model agents interpret these contracts as semantic affordances:
	•	Introspection: Fetch /openapi.json or CI descriptors to build an action graph.
	•	Planning: Choose compatible agents by schema match.
	•	Reflection: Adjust weights, delays, and mappings in real time.
	•	Learning: Store valid compositions as reusable ensembles.

The contract guarantees that the LLM can reason safely over heterogeneous domains without guessing untyped operations.

---

##  Security & Provenance

	•	All OpenAPI traffic follows OAuth 2 / mTLS; MIDI 2.0 bridges use local ACL tokens.
	•	Each agent signs its descriptor with x-agent-signature (SHA-256 over schema digest).
	•	Provenance metadata (created, modified, firmware, gitSHA) must be exposed in both forms.

--- 

## Versioning & Compliance

| Item | Rule |
|------|------|
| **Contract Version** | `fountain.ai/interoperability/v1` |
| **Spec Versions** | OpenAPI ≥ 3.1.0, MIDI-CI ≥ 1.2 |
| **Compliance Tests** | `fountain-validator run --agent <id>` must pass before release |
| **Drift Policy** | Breaking schema change → new major; additive → minor |


--- 

## Example Descriptor (Hybrid Agent)

```yaml 
x-agent-id: "fountain.ai/agent/sound/spectralizer"
x-agent-kind: "hybrid"
x-agent-version: "1.3.0"
info:
  title: "Spectralizer Hybrid Instrument"
  version: "1.3.0"
  description: "FFT-based timbral morphing engine accessible via HTTP and MIDI 2.0"
x-agent-protocols:
  - openapi-3.1
  - midi-ci-pe
x-agent-capabilities:
  - analyzeSpectrum
  - morphTimbre
  - renderAudio  
```

--- 

## Philosophical Note

In FountainAI, composability is musicianship:
	•	APIs perform like instruments.
	•	Instruments document themselves like APIs.
	•	LLMs conduct both through a single semantic score.

This contract exists to ensure that every agent—synthetic or human-built—can listen, respond, and evolve in time.

--- 

```txt
Maintainers:
FountainAI Core Architecture Group
https://fountain.coach/specs/AGENTS.md
Contract Version: 1.0.0
```
