# FountainFlow — Node Editor for FountainKit

FountainFlow is a Swift package that provides a per‑node‑flexible node/wire editor designed for FountainKit’s needs (Stage nodes, baseline‑aligned ports, custom bodies), while honoring our ancestor editors (Quartz Composer, Vuo, Plogue Bidule) and building on lessons from AudioKit’s Flow.

Why
- We need Stage nodes to be “node = page” with ports at baseline midpoints, HUD ticks, and custom body rendering. Flow’s global layout/style model can’t deliver this per node.
- We need per‑node layout and body hooks without forking our entire canvas stack.

What
- A small, focused library that initially wraps/bridges AudioKit Flow for wires/gestures, then evolves to first‑class per‑node style and rect providers.
- Early goals:
  - Hide node body for selected node kinds (Stages) and let clients render their own body.
  - Provide a rect provider so inputs can align to arbitrary anchors (e.g., Stage baselines).
  - Keep Flow’s solid pan/zoom/selection/wire gestures while we iterate.

Roadmap
- v0: Flow interop layer, type surface, per‑node body suppression, port rect adapters.
- v1: Native renderer with per‑node `NodeStyleProvider` and `NodeRectProvider`.
- v2: Snapshot harness + numeric invariants (fit/center, spacing).

License and attribution
- Honors AudioKit Flow and our ancestors (Quartz Composer, Vuo, Plogue Bidule). We’ll upstream good ideas where possible and clearly mark diverging design.
