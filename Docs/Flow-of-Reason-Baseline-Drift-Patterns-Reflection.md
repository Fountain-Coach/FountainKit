# Flow of Reason: Baseline → Drift → Patterns → Reflection

This document defines the sentence-level calculus that turns saved website pages into durable knowledge, and shows how to persist every step via the Awareness API using curl.

Why this exists: We stop “telling the model to go deeper” and instead produce concrete, cited artifacts on every cycle, guaranteeing that we always have something in memory.

## Concepts (plain language)

- Saved page: a single web page we visited and stored, with its title and URL.
- Paragraph evidence: short, readable paragraphs we extracted from those pages (2–5 sentences each). These are our evidence units.
- Baselineₙ: 6–12 complete sentences that summarize what the site is, who it’s for, what it offers, how it works, pricing and proof — each sentence ends with a citation [Title](URL) to a saved page.
- Driftₙ: the typed diff between Baselineₙ and Baselineₙ₋₁ — Added / Changed / Removed — each expressed as a sentence with citations.
- Patternsₙ: 3–6 recurring themes visible across baselines and history, each a sentence with citations.
- Reflectionₙ: a short analysis of baseline drifting patterns — 4–7 sentences that explain what changed and why, with citations where relevant.

After Baseline₂, we switch from “learning” to “tracking.” Baseline₃ and onward are tracking snapshots; every new cycle emits Drift, Patterns, and a Reflection.

## Deterministic calculus

1) Evidence packet
- Select 8–32 diverse paragraph evidence items (titles + URLs included), max 3–4 per page, prioritize canonical pages: Home, About, Product/Features, Pricing, Docs/Overview, Customers/Case Studies, Security, Legal.

2) Compose Baseline (sentence-level)
- Use the packet to write 6–12 bullets. Each bullet is a complete sentence and MUST end with a citation [Title](URL). If no model is available, build bullets directly from the evidence paragraphs and attach the source link.

3) Typed Drift (deterministic)
- Align new bullets to previous bullets with token overlap on names, entities, numbers.
- Emit sentences prefixed with “Added: …”, “Changed: …”, “Removed: …” preserving citations.

4) Patterns
- Cluster sentences by entities/topics across baselines and drifts; emit 3–6 stable, recurring themes, with citations.

5) Reflection
- 4–7 sentences analyzing the drift and patterns, focusing on impact and what it means now. Reference citations already present in bullets.

## API endpoints used

Awareness API (OpenAPI under `Packages/FountainServiceKit-Awareness`):
- POST `/corpus/baseline` — add Baseline
- POST `/corpus/drift` — add Drift
- POST `/corpus/patterns` — add Patterns
- POST `/corpus/reflections` — add Reflection
- GET `/corpus/history/{corpus_id}` — list history
- GET `/corpus/summary/{corpus_id}` — summarize history

All requests use JSON bodies. Replace `$AWARENESS_URL` and `$CORPUS_ID` accordingly.

## curl examples

Assumptions:
- `AWARENESS_URL=http://127.0.0.1:8001`
- `CORPUS_ID=memchat-app`

### 1) Add Baseline

```
curl -sS -X POST "$AWARENESS_URL/corpus/baseline" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "baselineId": "baseline-'
      "$(date +%s)"'",
    "content": "- What it is — complete sentence. [Home](https://example.com)\n- Who it is for — complete sentence. [About](https://example.com/about)\n- What it offers — complete sentence. [Features](https://example.com/features)\n- How it works — complete sentence. [Docs](https://example.com/docs)\n- Pricing — complete sentence. [Pricing](https://example.com/pricing)\n- Proof — complete sentence. [Customers](https://example.com/customers)"
  }'
```

Notes:
- `content` is the full, multi-line bullet list (each bullet a sentence, each ending with a citation).

### 2) Add Drift (typed diff)

```
curl -sS -X POST "$AWARENESS_URL/corpus/drift" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "driftId": "drift-'
      "$(date +%s)"'",
    "content": "Drift since last baseline: 2 added, 1 changed, 0 removed.\nAdded: New plan added — sentence with citation. [Pricing](https://example.com/pricing)\nChanged: Feature limit increased — sentence with citation. [Docs](https://example.com/docs)"
  }'
```

### 3) Add Patterns

```
curl -sS -X POST "$AWARENESS_URL/corpus/patterns" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "patternsId": "patterns-'
      "$(date +%s)"'",
    "content": "- Focus on enterprise security and SSO. [Security](https://example.com/security)\n- Emphasis on rapid onboarding. [Docs](https://example.com/docs)\n- Frequent pricing experiments. [Pricing](https://example.com/pricing)"
  }'
```

### 4) Add Reflection

```
curl -sS -X POST "$AWARENESS_URL/corpus/reflections" \
  -H 'Content-Type: application/json' \
  -d '{
    "corpusId": "'$CORPUS_ID'",
    "reflectionId": "reflection-'
      "$(date +%s)"'",
    "question": "tracking-cycle",
    "content": "Compared to the previous baseline, the vendor added an entry-level plan and raised usage caps, signaling a land-and-expand strategy. Security positioning remains strong (SSO, compliance). Customer evidence still highlights mid-market adoption. [Pricing](https://example.com/pricing) [Security](https://example.com/security) [Customers](https://example.com/customers)"
  }'
```

### 5) Inspect history and summary

```
curl -sS "$AWARENESS_URL/corpus/history/$CORPUS_ID" | jq .
curl -sS "$AWARENESS_URL/corpus/summary/$CORPUS_ID" | jq .
```

## Practical cycles

- Initial (Baseline₁):
  1) Ingest host (depth ~2, ~12 pages). Ensure paragraph evidence exists.
  2) Compose and POST Baseline₁ (sentences + citations).

- Completeness (Baseline₂):
  1) Target canonical pages (pricing/docs/customers/security), ingest more if missing.
  2) Compose and POST Baseline₂; compute and POST Drift₂; POST Patterns₂; POST Reflection₂.

- Tracking (Baseline₃ and onward):
  1) Refresh evidence (recrawl changes or focused endpoints).
  2) Compose and POST Baseline₃; compute and POST Drift₃; POST Patterns₃; POST Reflection₃.
  3) Repeat only on change signals (age > N days, sitemap changes, pricing/doc deltas), otherwise post Drift/Reflection for small updates without re-baselining.

## Sentence quality checklist

- Each bullet is one complete, specific sentence.
- Every bullet ends with a citation [Title](URL) to a saved page.
- No hedging (“might”, “appears”); state what the source says.
- Keep bullets short; avoid joining disjoint ideas.

## Operational guardrails

- If no baseline exists yet, produce a minimal Baseline from available evidence so downstream drift/patterns/reflection always have payloads.
- If evidence is thin (few pages, low paragraph quality), do not fabricate text — ingest more or run a quick re-segmentation pass to extract paragraphs.

---

For developers: MemChatKit exposes `buildBaselineAndArtifacts(for:host, level:)` which orchestrates evidence selection, baseline composition, typed drift, patterns, and reflection, persisting via Awareness API with FountainStore fallback.

