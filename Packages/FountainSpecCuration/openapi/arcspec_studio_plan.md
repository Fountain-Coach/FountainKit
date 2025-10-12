# ArcSpec & Studio Implementation Plan

This plan operationalises the two concept papers:

- `FountainKit Concept Paper_ Swift as the LLM Superpower.pdf`
- `PRESETS - From Imagintation to Interface.pdf`

It focuses on converting ArcSpecs into deterministic Swift tools that run inside
FountainKit’s sandbox while remaining spec-first.

---

## Vision

Build a self-extending “spec → Swift → sandbox” loop where the LLM can:

1. Capture emerging corpus patterns as ArcSpecs.
2. Compile ArcSpecs into OpenAPI + Swift clients automatically.
3. Orchestrate sandboxed “studios” (small Swift mains) that compose generated clients.
4. Feed resulting artifacts back into the corpus so new ArcSpecs evolve.
5. Audit and replay every action deterministically.

## Milestones

### M1 — ArcSpec → OpenAPI Spine
- [ ] Define ArcSpec YAML schema (arc metadata, operators, resources, guarantees).
- [ ] Build ArcSpec compiler that emits OpenAPI specs with FountainCore conventions.
- [ ] Integrate compiler into CI: change to ArcSpec regenerates specs and runs `lint-matrix.sh`.
- [ ] Document ArcSpec authoring (`docs/ArcSpec.md` with examples/operator taxonomy).
- [ ] **Seed persistence corpus:** (CLI ready) use `persistence-seeder` to derive speeches from `the-four-stars` and ingest them into FountainStore as baseline data before ArcSpec derivation.

### M2 — Sandboxed Studios
- [ ] Harden Swift sandbox image (non-root, read-only FS, dropped caps, quotas, logging).
- [ ] Extend tool registry to ingest generated clients + execution policy metadata.
- [ ] Deliver initial studios:
  - `ConcordanceStudio` (echo.align → echo.condense)
  - `PolyphonyStudio` (motif → rhythm transpose)
  - `MirrorStudio` (argument weave)
- [ ] Provide CLI (`fk studio run …`) and tests for studio execution.
- [ ] Establish artifact layout (`/data/corpora/<id>/studios/<studio>/<ts>/…`).

### M3 — Evolution Loop & Governance
- [ ] Build replay/diff tooling (`fk studio replay <run-id>`; visual diff for lattices/motifs).
- [ ] Ingest studio artifacts back into corpus; trigger arc re-derivation jobs.
- [ ] Add policy engine hooks (approvals, killswitch, audit dashboard).
- [ ] Ship first evolution pass: revise ArcSpec, regenerate clients, re-run studios end-to-end.

## Supporting Tracks

| Track | Goals |
| --- | --- |
| **Sandbox hardening** | seccomp/AppArmor, network allowlist, resource limits, hash+log every Swift snippet, SPM cache vendoring. |
| **Registry & Transport** | Ensure all generated clients rely on FountainCore transports; register new tools with network policy + quotas. |
| **Corpus Seeding** | Build ingestion pipeline that maps the `the-four-stars` GitHub corpus (texts, translations, annotations) into FountainStore collections before deriving ArcSpecs; maintain reproducible seed scripts. |
| **DX & Documentation** | Demo repo + Dockerfile showing the full loop; studio authoring guide; ArcSpec examples; lint workflow (`lint-matrix.sh`). |
| **Observability** | Structured logs (code hash, stdout/stderr, exit status), artifact indexing, Grafana/Kibana dashboards for tool executions. |

## Success Metrics

- 100% of ArcSpecs auto-generate OpenAPI + Swift clients with zero hand edits.
- ≥3 studios packaged, replayable, and producing deterministic artifacts.
- Sandbox audit log coverage: 100% of studio runs have searchable logs + artifacts.
- Policy engine can block or approve studio executions within 1s.
- First evolution cycle completed (artifact → new ArcSpec → regenerated studio).

## Dependencies & Risks

- Requires stable access to OpenAPI specs and Apple’s Swift OpenAPI Generator.
- Sandbox image must ship with pre-resolved SPM dependencies to avoid runtime fetch.
- Policy engine & observability must keep pace with studio proliferation.
- Ensure lint + CI cycles stay under rate limits (use `lint-matrix.sh` per spec).

## Next Check-in

- Track progress in this plan and surface status in `implementation_plan.md`.
- Update checklist items as milestones land; attach links to PRs/demos in-line.

---

Maintainers: keep this document synced with the concept papers and the
implementation reality of FountainKit studios.
