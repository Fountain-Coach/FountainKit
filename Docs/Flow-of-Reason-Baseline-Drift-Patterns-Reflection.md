# Drift–Pattern Reflection Calculus (Minimal Spec)

This calculus is independent of ingestion or domain. It defines how we reason from one baseline to the next using only sentence‑level claims.

## Objects

- Claim: a single, standalone sentence (optionally with a citation).
- Baselineₙ (Bₙ): ordered list of Claims representing “what is true as of now”.
- Driftₙ (Dₙ): typed diff between Bₙ and Bₙ₋₁ as Claims prefixed with Added/Changed/Removed.
- Patternsₙ (Pₙ): 3–6 recurring themes across B≤ₙ and D≤ₙ, each as a Claim.
- Reflectionₙ (Rₙ): 4–7 Claims that analyze Dₙ with reference to Pₙ.

Formal:
- Dₙ = Diff(Bₙ, Bₙ₋₁)
- Pₙ = Cluster(B₁..ₙ, D₁..ₙ)
- Rₙ = Reflect(Dₙ, Pₙ)

## Typed Diff (deterministic)

Given Bₙ and Bₙ₋₁ (lists of Claims):
1) Normalize for comparison (lowercase, strip punctuation except URIs) but keep originals for output.
2) Align by token overlap on entities/numbers/keywords (greedy; thresholded).
3) Emit labels:
   - Added: present in Bₙ only.
   - Removed: present in Bₙ₋₁ only.
   - Changed: aligned but materially different (numbers/dates/entities).
4) Prepend a summary Claim: “Drift since last baseline: A added, C changed, R removed.”

## Patterns

Cluster Claims by shared entities/keywords; keep clusters with support ≥ 2. Emit 3–6 concise, neutral Claims.

## Reflection

Construct 4–7 neutral Claims:
- S1: quantitative drift summary (A/C/R).
- S2–S5: highest‑impact changes tied to relevant Patterns (what/why/so‑what).
- Sfinal: near‑term implication or watchpoint.

## Quality Rules

- Claims are complete sentences; no fragments or placeholders.
- Be specific when known (names, numbers, dates); avoid hedging.
- One idea per sentence; citations optional but encouraged.

## Minimal Loop

1) Produce B₁ (current truths).
2) When state changes, produce B₂.
3) For each subsequent Bₙ: compute Dₙ, derive Pₙ, compose Rₙ, and persist all. If change is minor, emit Dₙ and Rₙ without creating a new baseline.
