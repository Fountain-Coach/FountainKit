# Bye‑Bye, CoreMIDI

_Thank you for the music. Now let’s talk about the future._

There comes a moment in every codebase when an old friend deserves a proper farewell. For us, that friend is CoreMIDI. It has been the sturdy bridge between software and sound for decades. It taught generations of apps how to talk, sing, and sometimes even scream at synthesizers. We’re grateful for the history and the music it enabled.

And yet, the road ahead asks for different qualities than the road behind. FountainKit is committing to a CoreMIDI‑free future, built on our MIDI 2.0 stack (RTP/BLE) and an explicit Loopback transport for tests and in‑process IPC. Today, we’re lovingly retiring CoreMIDI from this repository.

## Why now?

Short answer: modern Swift and cross‑platform determinism.

Longer answer:

- Concurrency safety: CoreMIDI’s callback‑based C API doesn’t map cleanly onto Swift 6’s strict concurrency model. Force‑fitting it means a pile of `@unchecked Sendable`, thread hops, and a growing potential for races or deadlocks. We want explicit actor isolation and predictable semantics all the way down.
- UI stability: We’ve hit real‑world stalls when the daemon wobbled (e.g., waiting inside `MIDIDestinationCreateInternal`). A single hang on the UI thread is one hang too many. Our instrument stack must self‑heal, not freeze.
- Determinism & testability: Our robot and snapshot tests must run headless on CI, on macOS and Linux, without hidden daemons. Loopback + RTP/BLE give us reproducible UMP logs and exact replays. CoreMIDI doesn’t.
- Portability: FountainKit targets macOS and Linux. CoreMIDI is macOS‑only. Enough said.
- Observability: Our UMP‑first path gives transparent timing and transport introspection. Less magic, more science.

This isn’t a judgment on the value CoreMIDI has delivered (it delivered plenty). It’s a statement about the shape of the system we’re building next: deterministic, testable, portable.

## What replaces it?

We standardize on three transports:

- Loopback (in‑process) — a zero‑dependency transport that keeps tests and local IPC snappy and deterministic.
- RTP MIDI 2.0 — stable networking with proper timing semantics.
- BLE MIDI 2.0 — wireless when it helps; same abstractions, no CoreMIDI.

All three sit behind our `midi2` abstractions and the UMP model. Tests drive real UMP, we record `.ndjson`, and we replay exactly.

## A gentle note of irony

If you’ve ever shipped a demo fifteen minutes before showtime, you’ll recognize the vintage move: “Just one more CoreMIDI call, what could go wrong?” And then you watch a beachball spin because the daemon felt philosophical. We’ve all been there. We’ll remember it fondly, and we’ll build a future where last‑minute fixes don’t require bargaining with background services.

## What changes for you?

- No `import CoreMIDI` anywhere in this repository. No conditional imports. No C API calls. Period.
- Prefer `MIDI2SystemInstrumentTransport(backend: .rtpFixedPort(..))`, the BLE backend, or the Loopback transport for local flows.
- Tests and tools talk to instruments by identity and UMP—deterministic, scriptable, and replayable.

If you truly need a CoreMIDI bridge for legacy hardware, keep it in a separate repository and isolate it at process boundaries. We won’t merge CoreMIDI back into FountainKit.

## FAQ

Q: Can we keep a hidden “turn CoreMIDI back on” flag?

A: No. Flags leak types and build‑graph edges into CI and local builds, and they quietly re‑introduce the very instability we’re removing. If you must experiment, do it out‑of‑tree.

Q: How do we route to MIDI‑1 devices without CoreMIDI?

A: We stay UMP‑first and use explicit downgrade/filters at the edges. BLE/RTP peers and the sampler bridge are the supported paths. Internally, timing and identity stay MIDI 2.0.

Q: What about virtual endpoints?

A: Use the Loopback transport. It’s explicit, deterministic, and identical on macOS and Linux.

## Migration timeline

- CoreMIDI targets and tests were removed from this tree. Any remaining mentions live only in vendored history or external repos.
- A Loopback stub exists to preserve call sites while we complete the `midi2` rollout.
- CI lint enforces the hard rule: no `import CoreMIDI`, no `MIDI*Create*`, no `MIDISend*`.

## How to test the new world

- Run focused editor tests: `Scripts/dev/test-fountain-editor-all` (fast, headless).
- Exercise transports with the robot: drive UMP, assert numeric invariants, inspect `.fountain/artifacts`.
- Capture and replay: confirm the timeline is identical on your laptop and on CI.

## A thank‑you, sincerely

To the engineers behind CoreMIDI: thank you. You enabled decades of creativity and a generation of apps. We leave the dance floor with gratitude. Now we’ll try a different rhythm—one that’s actor‑safe, reproducible, and portable—so the music keeps playing for everyone, everywhere.

Here’s to a brighter (and less beachbally) future.

