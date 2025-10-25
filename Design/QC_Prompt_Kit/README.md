# QC-Prompt Kit

A minimal, transferable package defining the **Quartz Composer–inspired Prompt Language** for GUI mocking and creation.

## Contents

1. **qc_prompt.dsl** — Human-readable DSL describing the canvas, nodes, ports, and edges.
2. **qc_prompt.json** — Machine-normalized JSON equivalent.
3. **qc_prompt.svg** — Visual mock rendering using cubic Bézier noodles.
4. **README.md** — Reasoning, documentation, and rules.

## Design Reasoning

The goal is to unify human-readable composition prompts with deterministic generation targets (SVG + SwiftUI). The QC feel is preserved by using horizontal-tangent cubic Béziers and node-box metaphors.

### Core Insights
- **Nodes and Ports:** Minimal node schema enables fast layout and serialization.
- **Edges:** Horizontal-tangent Béziers recreate QC’s flowing, musical feel.
- **Validation Layers:** Hard/Soft/Correction rules ensure predictable autolayout.
- **Targets:** Both SVG and SwiftUI backends share identical anchor math.

### Generator Pipeline
1. Parse DSL → AST
2. Apply defaults and correction logic
3. Validate (IDs, ports, edges)
4. Layout (flowLR or absolute)
5. Generate SVG and SwiftUI

### Coordinate System & Grid (preview)
- For absolute placement, authors need a visible coordinate system.
- Use the preview renderer to see a numbered grid and node positions:
  - `bash Scripts/design/qc-render.sh --kit Design/QC_Prompt_Kit`
  - Output: `Design/QC_Prompt_Kit/qc_preview.svg` (includes a numbered grid, axes, nodes, ports, and edges).
- Grid density comes from `canvas grid=<N>`; numbers label both axes in grid units.

---

Author: FountainAI Codex Companion
Date: 2025-10-25
