# Migration Tracker — FountainKit

Scope
- Tracks concrete deliverables from the Migration Plan (From Multi‑Service OpenAPI to Unified MIDI‑2 Runtime).
- Single source for status. Keep terse; link to code/paths.

Status Key
- [x] done, [~] in progress, [ ] pending, [P] prototype (parked)

Phase 1 — Inventory & Classification
- [x] Service inventory doc: `specs/Migration-Inventory-2025-11-12.md:1`
- [ ] Owners assigned per service (planner, function-caller, persist, gateway)
- [ ] Classification confirmed (pure-logic, light-state, external/heavy)

Phase 2 — Transcode to MIDI‑2 Agents (spec-first)
- [x] Facts schema locus decided: FountainStore `agent-facts:facts:agent:<safeId>`
- [x] Planner facts (PE mappings): `agents/planner-pe-facts.yaml`
- [x] Function Caller facts (PE mappings): `agents/function-caller-pe-facts.yaml`
- [x] Persist facts (PE mappings): `agents/persist-pe-facts.yaml`
- [ ] Facts acceptance criteria (round‑trip JSON ⇄ PE) documented under `specs/`
- [ ] Service owners sign off on facts

Phase 3 — Unified Host (design only in this cycle)
- [ ] Host responsibilities sketched (PE decode/encode, HTTP adapters, timing model)
- [ ] Interaction with gateway clarified (what remains public HTTP)

Infrastructure & Hygiene
- [x] Domain switch to `fountain.coach` across schema/validator/docs: see `git log` 9ff1082
- [x] Gateway serves descriptor: `/.well-known/agent-descriptor`
- [x] Gateway serves facts: `/.well-known/agent-facts`
- [x] Curl smoke for gateway well-known: `Scripts/ci/gateway-well-known-smoke.sh`
- [x] CI lint forbids `fountain.ai`: `.github/workflows/domain-lint.yml`

Prototypes (parked; not required for Phase 2 sign‑off)
- [P] Loopback PE bridges (planner, function-caller, persist) under `Packages/FountainApps/Sources/*-pe-bridge`
- [P] SysEx7 JSON loopback tools (sender/receiver) under `Packages/FountainApps/Sources/sysx-json-*`

Near‑Term Next
- [ ] Assign owners and confirm service classifications
- [ ] Add “Facts acceptance criteria” to `specs/` and link from `specs/Migration Plan.md`
- [ ] Seed facts in canonical store via a one‑shot script (owners run locally)

