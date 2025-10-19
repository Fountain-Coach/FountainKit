# Drift–Pattern Reflection Calculus (Domain‑agnostic)

This document defines the calculus for reasoning over baselines. It is intentionally independent of how content is ingested. The only assumption is that a corpus holds sentence‑level claims (optionally with citations).

## Core objects

- Claim: a single, standalone sentence. Optionally ends with a citation like [Label](URI). Examples are domain‑agnostic (product facts, project state, research findings, etc.).
- Baselineₙ (Bₙ): an ordered list of Claims representing “what is true as of now”.
- Driftₙ (Dₙ): the typed diff between Bₙ and Bₙ₋₁, expressed as Claims prefixed with Added/Changed/Removed.
- Patternsₙ (Pₙ): 3–6 recurring themes observed across prior baselines and drifts, each as a Claim.
- Reflectionₙ (Rₙ): a short analysis composed from Dₙ and Pₙ — 4–7 Claims that explain the change and its implications.

Formal view:
- Dₙ = Diff(Bₙ, Bₙ₋₁) → {Added, Changed, Removed}×Claim
- Pₙ = Cluster(B₁..ₙ, D₁..ₙ) → Claim*
- Rₙ = Reflect(Dₙ, Pₙ) → Claim*

## Typed diff (deterministic)

Input: two lists of Claims, Bₙ and Bₙ₋₁.
1) Normalize (lowercase, strip punctuation except URIs) to compare content tokens; keep original text for output.
2) Align by similarity (token overlap on entities/numbers/keywords). Greedy match with a minimum overlap threshold.
3) Emit:
   - Added: Claims in Bₙ with no aligned partner in Bₙ₋₁.
   - Removed: Claims in Bₙ₋₁ with no aligned partner in Bₙ.
   - Changed: Aligned pairs whose text differs meaningfully (e.g., numbers/dates/entities changed).
4) Prepend labels (Added:/Changed:/Removed:) to the output Claims.
5) Summary line: “Drift since last baseline: A added, C changed, R removed.”

This works for any domain: roadmaps, datasets, minutes, inventories, etc.

## Patterns (lightweight)

Group Claims from B₁..ₙ and D₁..ₙ by shared keywords/entities; keep clusters with at least two members. Emit 3–6 Claims that describe the consistent themes (stable truths, repeated motions, ongoing risks). Citations are optional.

## Reflection

Rₙ is an analysis over Dₙ and Pₙ:
- S1: quantitative drift summary (A/C/R counts).
- S2–S5: the highest‑impact changes tied to relevant Patterns (what changed and why it matters).
- Sfinal: near‑term implication or “what we watch next”.

Reflections remain sentence‑level and neutral; they can include citations that are already present in input Claims.

## Awareness API

We persist the calculus via Awareness endpoints (OpenAPI under `Packages/FountainServiceKit-Awareness`). Bodies are plain text; the service is content‑agnostic.

- POST `/corpus/baseline` — add Baseline (content is your Bₙ list of sentences)
- POST `/corpus/drift` — add Drift (content is your Dₙ sentences incl. summary)
- POST `/corpus/patterns` — add Patterns (content is your Pₙ sentences)
- POST `/corpus/reflections` — add Reflection (content is your Rₙ sentences)

Replace `$AWARENESS_URL` and `$CORPUS_ID` accordingly.

### Baseline (generic example)

```
curl -sS -X POST "$AWARENESS_URL/corpus/baseline" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "baselineId": "baseline-'"$(date +%s)"'",
    "content": "- The project tracks three workstreams and weekly milestones.\n- Stakeholders receive a Friday status digest.\n- Risk reviews occur biweekly with owners assigned."
  }'
```

### Drift (generic example)

```
curl -sS -X POST "$AWARENESS_URL/corpus/drift" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "driftId": "drift-'"$(date +%s)"'",
    "content": "Drift since last baseline: 1 added, 1 changed, 0 removed.\nAdded: A fourth workstream was initiated for QA automation.\nChanged: Risk reviews moved from biweekly to weekly cadence."
  }'
```

### Patterns (generic example)

```
curl -sS -X POST "$AWARENESS_URL/corpus/patterns" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "patternsId": "patterns-'"$(date +%s)"'",
    "content": "- Cadence increases during integration phases.\n- Governance relies on short, frequent checkpoints.\n- New workstreams cluster around quality and tooling."
  }'
```

### Reflection (generic example)

```
curl -sS -X POST "$AWARENESS_URL/corpus/reflections" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "reflectionId": "reflection-'"$(date +%s)"'",
    "question": "tracking-cycle",
    "content": "We expanded scope with a QA automation stream and tightened risk cadence, consistent with the pattern of increasing checkpoints during integration. The next focus is stabilizing cross‑team interfaces and measuring cycle time."
  }'
```

### Inspect history

```
curl -sS "$AWARENESS_URL/corpus/history/$CORPUS_ID" | jq .
curl -sS "$AWARENESS_URL/corpus/summary/$CORPUS_ID" | jq .
```

## Quality rules (domain‑agnostic)

- Claims are complete sentences, not fragments.
- Be specific (names, numbers, dates, owners) when known.
- Keep one idea per sentence; avoid hedge words unless uncertainty is the point.

## Minimal loop

1) Write B₁ (current truths). 2) Write B₂ when state materially changes. 3) For each new Bₙ: compute Dₙ, then Pₙ, then Rₙ and persist all. If change is minor, you can post Dₙ and Rₙ without a new baseline.

