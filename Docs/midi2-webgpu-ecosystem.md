# MIDI 2.0 + WebGPU Backplane (No HTTP)

This paper lays out the vision for a FountainAI ecosystem that runs entirely on a MIDI 2.0 pub/sub backplane and uses WebGPU as its deterministic compute and rendering plane. HTTP and OpenAPI are absent by design; the transport, timing, schema, and observability all live within MIDI. FountainStore remains the shared memory for schemas, capabilities, prompts, and session descriptors so every participant runs against the same contract.

MIDI 2.0 is the rail network. WebGPU is the compute lab on that network. FountainStore is the campus registry and logbook. Messages travel as timestamped trains with labeled cargo; runtimes validate tickets, keep time, and deliver results. The net effect is an environment where instruments, GPU workloads, and LLM tools collaborate with low overhead and high determinism.

## Primitives and Definitions

Backplane: MIDI 2.0 UMP carries every command, event, telemetry packet, and resource coordination message. There is no client/server asymmetry; peers publish and subscribe on topics.

Topic: A routable address on the backplane (for example `gpu/pipeline.create`, `gpu/job.dispatch`, `llm/tool.invoke`, `telemetry/jitter`). Each topic has a declared payload schema, timing budget, and optional response topic.

Envelope: A mandatory header on every message: topic id, schema version, correlation id, timestamp, QoS flag, session id, capability mask, and optionally chunk metadata. Encoded in SysEx8 or a reserved profile. Anything that lacks a valid envelope is rejected or quarantined.

Session: A negotiated contract between peers that sets the clock source, jitter budget, maximum payload size, capability set, and a resume token. Sessions are stored in FountainStore to allow recovery, audit, and deterministic re-entry after loss.

Capability mask: A scoped permission set attached to a session. Masks define which topics a peer may publish or subscribe to and with what QoS. Secrets live in SecretStore/FountainStore and are bound to sessions, never embedded in payloads.

Schema: A MIDI-native interface definition that replaces OpenAPI. It defines payload fields, error codes, QoS semantics, and timing budgets per topic. It is versioned, reviewed, and stored in FountainStore.

Facts: Generated descriptors derived from the schema that describe topics, payload shapes, capabilities, expected responses, and timing budgets for LLM tools. Facts are stored and served from FountainStore so tool hosts and instruments share the same view.

Runtimes: `midi2.js` (browser) and `midi2.swift` (native) implement the backplane, enforce envelopes, load schemas and facts from FountainStore, and bind topic traffic to WebGPU or other capabilities.

Compute plane: WebGPU executes pipelines and jobs declared over MIDI. Messages describe what to run; WebGPU performs the work; results return on MIDI topics with correlation ids and timestamps.

## Narrative Picture

Imagine a clocked campus with a central rail. Every building is a capability: a GPU lab, an LLM workshop, a telemetry tower. Trains carry labeled cargo with precise departure times, and only riders with the right badges board. The registry at the gate lists buildings, rooms, allowed cargo, and who may enter. Station masters (the runtimes) keep time, validate tickets, and route trains. A GPU job is simply a train carrying a pipeline id, buffers, and a dispatch plan to the lab; results take the return rail with the same correlation tag. Nothing leaves the rail; everything remains time-aware, auditable, and observable.

## WebGPU Binding on MIDI

GPU artifacts live as identifiers in the schema and metadata in FountainStore: WGSL module ids, bind group layouts, pipeline ids, buffer and texture descriptors. Topic traffic activates them:

- `gpu/pipeline.create` submits WGSL source ids and layouts; the runtime compiles, validates, and returns a pipeline id plus diagnostics.
- `gpu/buffer.write` streams chunked data with checksums; QoS and chunk metadata ensure integrity and allow retransmit.
- `gpu/job.dispatch` declares pipeline id, bind groups, workgroup sizes, push constants, and latency/jitter budgets; responses on `gpu/job.result/<corr>` report status and outputs or output refs.
- `gpu/buffer.read` extracts buffer content through chunked responses with verification.

All GPU operations respect the envelope: correlation for pairing requests and results, timestamps for scheduling and SLA checks, and capability masks for access control. Runtimes measure observed latency and jitter per topic and emit telemetry if budgets are exceeded.

## Timing, QoS, and Recovery

Timestamps in envelopes anchor scheduling and allow peers to measure jitter. QoS codes state delivery expectations (at-most-once, at-least-once, exactly-once with replay tokens). Chunk metadata (chunk id, total, checksum) allows reliable transfer of larger payloads. Sessions carry resume tokens so peers can request backfill or repeat a dispatch after a gap. If timing budgets are missed, runtimes emit telemetry and may drop or downgrade late messages based on policy.

## Security and Policy

Capability masks gate topic access and QoS level. Session negotiation issues masks based on operator policy and stored secrets. Secrets remain in SecretStore/FountainStore and are bound to session descriptors, never serialized into MIDI payloads. Policies are auditable: who can publish to `gpu/job.dispatch`, who can subscribe to telemetry, and under what budgets.

## Persistence and Registry

FountainStore anchors the system: it holds the schema (the MIDI IDL), generated facts, topic registry, session descriptors (clock, jitter budgets, capability masks, resume tokens), and resource metadata (pipelines, buffers, textures). Peers boot by fetching these artifacts, refusing to proceed without them. Because the registry is canonical, every participant shares the same vocabulary and expectations.

## Observability

Telemetry topics (for example `telemetry/jitter`, `telemetry/errors`, `telemetry/resource-usage`) carry timing measurements, drops, retries, compilation diagnostics, and GPU utilization. Correlation ids and session ids tie events together. Operators can replay telemetry alongside session descriptors to reconstruct incidents and verify SLA adherence.

## LLM Tooling Without HTTP

LLM tools bind to topics, not routes. The facts generator (`midi-schema-to-facts`) produces descriptors that state the topic name, payload schema, required capabilities, timing budget, and expected response topic. An LLM publishes a tool invocation to `llm/tool.invoke` with a correlation id and listens on `llm/tool.result/<corr>`. GPU jobs, instrument controls, and telemetry subscriptions all follow the same pattern, making the tool surface uniform and typed.

## Implementation Path

First, author the MIDI schema: define topics, payload fields, envelopes, QoS codes, error codes, capability masks, and timing budgets; version it and store it in FountainStore. Second, build `midi-schema-to-facts` to translate that schema into tool descriptors and publish them to FountainStore. Third, extend `midi2.js` and `midi2.swift` to load schema and facts at boot, enforce envelopes and capability masks, implement the topic registry, handle chunking and checksums, and bind GPU topics to WebGPU APIs. Fourth, wire FountainStore workflows for session negotiation, capability issuance, resource metadata, and resume tokens. Fifth, add telemetry and conformance: tests for schema compliance, jitter and latency under load, chunk integrity, GPU correctness, and recovery after loss. Finally, update prompts and MRTS coverage to describe the MIDI-only transport, GPU topics, and timing budgets so robot runs stay aligned.

## The New World

In this model, MIDI 2.0 is the universal rail, and WebGPU is a first-class lab connected to it. Every action—GPU dispatch, LLM tool invocation, instrument control, telemetry—is a timed, typed message on the rail. FountainStore keeps everyone honest by anchoring schema, capabilities, and sessions. Runtimes enforce the contract, measure real-time behavior, and surface rich telemetry. The ecosystem becomes a clocked, observable, and secure mesh where computation, interactivity, and reasoning cohabit naturally on the MIDI backplane. The payoff is a deterministic, low-overhead path for user-facing LLMs to command GPU resources and instruments without ever leaving the MIDI fabric.
