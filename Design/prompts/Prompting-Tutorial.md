## Prompting Tutorial — From Onboarding to Mastery

This guide teaches you how to write effective prompts for two things we use in FountainKit:

1) Composition prompts (QC Prompt Kit DSL/JSON) — to design node‑based diagrams deterministically.
2) Visual prompts (image/SVG generation) — to produce consistent, on‑brand diagrams from text instructions.

The mindset: be a director, not a guesser. Name the scene, fix the camera, place the actors, and only then add style.

---

### Part 1 — QC Composition Prompts (DSL)

Mental model
- Canvas is your stage. Nodes are actors with named ports. Edges are lines they speak along.
- The DSL is declarative: you tell it where things live and how they connect; the renderer respects you.

Your first prompt
```
canvas 900x560 theme=light grid=24

node Source at (100,120) size (200,110) {
  port out right name:out type:data
}
node Sink at (520,280) size (200,110) {
  port in left name:in type:data
}

edge Source.out -> Sink.in style qcBezier width=3
autolayout none
```

Progressive refinement
- Start with `autolayout none` so the layout is predictable.
- Add ports explicitly — avoid magic defaults.
- Name edges by intent via a comment/note (use `note` in DSL) when helpful.

When to use flow
- `flowLR` is for narrative diagrams; renderer will place nodes left→right. Keep node sizes comparable and the story linear.
- `flowTB` (top→bottom) suits pipelines but keep long labels out of the main lane.

Mastery checklist
- Uniqueness: node IDs are unique; port names unique per node.
- Clarity: 2–4 ports per node, tops; split complex nodes.
- Readability: avoid overlapping nodes; snap to grid (`grid=24`) for alignment.
- Consistency: reuse node titles and types across diagrams.

Lint as a coach
- Run `bash Scripts/design/qc-lint.sh --kit Design/QC_Prompt_Kit` to catch: duplicate IDs, bad sides/dirs, orphan edges, and canvas mismatches.

---

### Part 2 — Visual Prompts (SVG/Image Generation)

Mental model
- The model is an illustrator with a good memory. If you fix style, canvas, and palette, results get consistent.

Stable scaffold
- Always specify: format (SVG, 1200×700), palette (neutral grays + accent #2F74FF/#00B3A4), labels, arrows, and layout.
- State nodes left→right or top→bottom and name each box.

Prompt template (fill‑in)
```
Create an SVG 1200×700, neutral gray palette with accents #2F74FF/#00B3A4.
Title: <diagram title>
Boxes (left→right): <Box A>, <Box B>, <Box C>.
Arrows: A→B, B→C with thick lines. Add small labels on arrows if helpful.
Fonts: system sans, large, legible.
Background: white or very light gray.
```

Common patterns
- Architecture: boxes with split arrows (fan‑out/fan‑in); add a control plane above.
- Flow: 4–5 boxes, no more; long labels become notes.
- Mapping: a left endpoint, a mapping block, a right buffer/renderer.

Style hygiene
- No drop shadows; use contrast and spacing.
- Keep 1–2 accent colors; avoid rainbow.
- Prefer verbs for arrows, nouns for boxes.

---

### Part 3 — The 3‑Path Process (Write → Prompt → Place‑In)

1) Write
- Draft the explainer or story first (plain text). Identify 3–5 diagrams the text needs. Name boxes and flows.

2) Prompt
- Use the template above or `Design/prompts/InstrumentBridge.image_prompts.md` to generate SVGs. Keep sizes and palette consistent.
- Iterate: if an element is ambiguous, rename it in the prompt. Remove anything cosmetic.

3) Place‑In
- Save over placeholder SVGs (same filenames) in `Design/diagrams/`.
- Re‑read the document and remove any diagram that repeats the obvious; diagrams earn their space.

---

### FAQ

Q: Why not auto‑layout everything?
- A: Determinism beats novelty in docs. Use flow modes when they help, but pin critical scenes absolutely.

Q: How do I keep diagrams “on brand”?
- A: Fix size, palette, and fonts up front; reuse the same template; avoid new colors unless they mean something.

Q: Can I mix audio/midi diagrams and UI graphs?
- A: Yes, but separate concerns: architecture vs interfaces. Use different titles and keep each diagram to one idea.

