At any given time `t`, the engine’s state for the puppet stage can be represented as:

- `time`: floating‑point seconds since an arbitrary start.
- `camera`:
  - `azimuth`: radians.
  - `zoom`: scalar.
  - (optionally) derived fields like `position` and `lookAt` for convenience.
- `bodies`:
  - list of named bodies (`bar`, `torso`, `head`, `handL`, `handR`, `footL`, `footR`),
  - for each: `position: {x, y, z}`, `velocity: {x, y, z}`.

This can be serialised as JSON for logs or debugging:

```json
{
  "time": 1.234,
  "camera": { "azimuth": 0.78, "zoom": 1.0 },
  "bodies": {
    "bar":   { "position": { "x": 0.0,  "y": 15.0, "z": 0.0 }, "velocity": { "x": 0.1, "y": 0.0, "z": 0.0 } },
    "torso": { "position": { "x": 0.0,  "y": 8.0,  "z": 0.0 }, "velocity": { "x": 0.0, "y": 0.0, "z": 0.0 } }
    // …
  }
}
```

The Swift engine does not enforce this schema directly, but snapshot helpers and tests should use these field names and shapes so other tools can rely on them.

