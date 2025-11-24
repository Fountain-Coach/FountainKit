This directory describes the authoring UX for the Teatro Stage Engine: how humans interact with the stage, puppet, and timeline when creating or editing scenes. It is not an implementation guide for any one renderer; instead, it sets expectations for features and flow that MetalViewKit, web, or other UIs should converge on.

Keep the focus narrow:
- the stage view (room + puppet + actors),
- a simple time bar (record, scrub, snapshots),
- and a tiny inspector (labels and numeric state).

Do not design a general 3D or DAW editor here. The goal is a Teatro‑specific authoring surface tuned for the puppet stage.
