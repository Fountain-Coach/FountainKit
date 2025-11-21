# AGENT — SVG Animation Renderer Instrument (Service)

This target exposes SVGAnimationKit over HTTP as an instrument‑ready renderer. It implements the `svg-animation` spec under `Packages/FountainSpecCuration/openapi/v1/svg-animation.yml`.

Position
- Library engine: `SVGAnimationKit` (external package).
- Service spec: `svg-animation.yml` mapped to `fountain.coach/agent/svg-animation/service`.
- Server entry: `svg-animation-service` in `Packages/FountainApps/Sources/svg-animation-service`.

Scope
- Minimal HTTP surface:
  - `POST /svg/scene` — static SVG from a scene description.
  - `POST /svg/scene/frames` — list of SVG strings for a scene + scalar timeline.
- No persistence, no MIDI, no Gateway logic; those live in FountainKit hosts and Tools Factory.

Notes
- Keep this service thin: decode JSON → build SVGAnimationKit types → render → return SVG.
- Treat this as a rendering instrument: facts/OpenAPI/PE wiring happen in FountainKit, not here.

