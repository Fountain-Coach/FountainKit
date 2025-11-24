# Teatro Engine Spec – Roadmap Notes

## Short-Term

- Validate `teatro-engine.yaml` against OpenAPI tooling.
- Add `/v1/styles/{styleId}` endpoint to expose style profiles (colors, stroke widths, camera presets).
- Add snapshot replay endpoint (`/v1/scenes/{sceneId}/replay`).
- Add first-class light endpoints and schemas (spot, wash, backlight) and a minimal reference implementation in the engine.

## Medium-Term

- Extend `PropType` with additional Teatro-native props (spotlight, curtains, railings).
- Formalize PuppetRig joint graph and expose more introspection (e.g. per-limb tension).
- Define event stream (WebSocket or SSE) for live puppet updates.

## Long-Term

- Multi-rig support (multiple puppets, light rigs, camera rigs).
- Serialization format for full Teatro performances (script + motion + semantics).
