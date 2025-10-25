## AGENT — Design/QC_Prompt_Kit

### Scope
- Path: `Design/QC_Prompt_Kit/**`.
- Purpose: Quartz Composer–inspired Prompt Kit for graph‑style GUI composition with a human DSL, normalized JSON, and deterministic render targets (SVG today; SwiftUI next).

### Files
- `qc_prompt.dsl` — Human DSL describing canvas, nodes, ports, edges, notes, layout.
- `qc_prompt.json` — Machine‑normalized JSON (IDs, coords, ports, edges, notes, layout).
- `qc_prompt.svg` — SVG rendering using QC‑style horizontal‑tangent cubic Béziers.
- `README.md` — Background, pipeline, and rules.
- `AGENTS.md` — Grammar, conventions, evolution plan.

### Grammar (EBNF sketch)
```
Document   := Header { Node | Edge | Note | Layout }
Header     := 'canvas' Int 'x' Int [ 'theme=' Ident ] [ 'grid=' Int ]
Node       := 'node' Ident 'at' '(' Int ',' Int ')' 'size' '(' Int ',' Int ')' '{' Port* '}'
Port       := 'port' Dir Side 'name:' Ident 'type:' Ident
Dir        := 'in' | 'out'
Side       := 'left' | 'right' | 'top' | 'bottom'
Edge       := 'edge' NodeRef '.' PortId '->' NodeRef '.' PortId Style
Style      := [ 'style' Ident ] [ 'width=' Number ] [ 'glow' ]
Note       := 'note' String 'at' '(' Int ',' Int ')'
Layout     := 'autolayout' ('none' | 'flowLR' | 'flowTB')
NodeRef    := Ident
PortId     := Ident
Ident      := /[A-Za-z_][A-Za-z0-9_\-]*/
Int        := /[0-9]+/
Number     := Int | Int '.' Int
String     := '"' ... '"'
```

- Identifiers are case‑sensitive; node IDs must be unique.
- Coordinates use a top‑left origin (SVG/SwiftUI aligned).

### Autolayout Modes
- `none` — absolute placement from `node at (x,y) size (w,h)`; renderers may snap to grid.
- `flowLR` — left→right flow by topological order; configurable gaps (future `gapX`, `gapY`).
- `flowTB` — top→bottom flow (future).

### Node Library & Defaults
- Minimal node schema: `title` defaults to `id`.
- Default ports: none — authors state ports explicitly to avoid hidden connections.
- Recommended library (non‑normative): `Source`, `Filter`, `Mix`, `Split`, `Sink` with conventional ports. Keep pure‑data `type` values (`data`, `event`, `audio`, `midi`).

### Edges & Bézier Routing
- `style qcBezier` uses cubic curves with horizontal tangents near nodes (QC feel).
- Control points computed from port side + radius; avoid crossing node bounds.
- Future: Manhattan routing (`ortho`) with rounded corners for dense graphs.

### Validation & Round‑Trip
- Hard checks: unique node IDs; existing port refs; valid sides/dirs; positive canvas size.
- Soft checks: overlapping nodes (warn); edges crossing notes (warn).
- Corrections: missing `title` → `id`; missing `style` → `qcBezier`; missing `width` → `2.0`.
- Round‑trip goal: `DSL → JSON → SVG → JSON` yields identical `nodes/edges/notes/layout` (order may differ). Add fixtures under `Design/QC_Prompt_Kit/tests/` when generators land.

### Render Targets
- SVG (current): anchor math is source of truth; top‑left origin; device‑independent units. Use `Scripts/design/qc-render.sh` to generate a numbered grid preview so coordinates are visible while authoring.
- SwiftUI (next): replicate anchor math 1:1 via a shared `LayoutEngine`.

### Conventions
- Grid default: `grid=24`; renderers may expose snap toggle.
- Numbered axes: preview renderer overlays labeled axes every grid step to avoid guessing coordinates.
- Theme: `theme=dark|light` hints background/ink; keep brand colors out of DSL.
- Numbers: widths are device‑independent; no units in DSL.

### Example (DSL)
```
canvas 900x560 theme=dark grid=24

node Source at (100,120) size (200,110) {
  port in  left  name:in   type:data
  port out right name:out  type:data
}

node Filter at (520,280) size (200,110) {
  port in  left  name:in   type:data
  port out right name:out  type:data
}

edge Source.out -> Filter.in style qcBezier width=3.5 glow
note "drag to connect…" at (620,230)

autolayout none
```

### Evolution Plan
- Formalize grammar (above) and publish JSON schema for `qc_prompt.json`.
- Add `flowTB` autolayout and `gapX/gapY` parameters.
- Provide a node library doc with canonical port sets.
- Create round‑trip tests and sample fixtures.
- Implement SwiftUI renderer with anchor parity to SVG.

### CI & Tooling (future)
- Add `Scripts/design/qcgen` wrapper to render DSL → JSON + SVG.
- Optional GitHub Action: lint DSL, validate round‑trip, attach SVG artifacts.

### Contribution Checklist
- DSL and JSON both updated (no drift).
- IDs, ports, and edges validated (no orphans).
- SVG anchors readable (avoid curves crossing boxes when possible).
- Keep examples small and composable.
