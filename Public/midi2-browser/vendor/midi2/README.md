# midi2.js — Real-Time Control Plane for WebGPU

midi2.js is a **spec-accurate, cross‑browser, CoreMIDI‑free implementation of the full MIDI 2.0 protocol stack**, reframed for 2025+ as a **general-purpose real‑time control plane** for WebGPU, DSP, ML inference, physics engines, XR, and agent‑based systems.

This project is *not* a music library.  
It treats MIDI 2.0 as it actually is:  
a **timestamped, structured, vendor‑agnostic event fabric** capable of driving heterogeneous compute systems.

---

## 1. Why MIDI 2.0 is Not a Music Protocol Anymore

MIDI 2.0 introduces:

- 32‑bit parameter resolution  
- micro‑timing via JR timestamps  
- UMP word-packet structures  
- structured SysEx7/8 envelopes  
- Profiles, Properties, Function Blocks  
- Flex Data (free-form structured metadata)

These features align MIDI2 with:

- GPU queue scheduling  
- ML kernel modulation  
- shader parameter automation  
- DSP graph control  
- motion/physics orchestration  
- haptics / XR device envelopes  

**MIDI 2.0 = real‑time compute coordination protocol.**

midi2.js implements this perspective completely.

---

## 2. Included in This Repository

### ✓ **Full UMP Encode/Decode**
- Channel Voice 1.0 & 2.0  
- System / Utility / Stream / Function Blocks (incl. Process Inquiry 0x03)  
- Per‑Note Management, RPN/NRPN, Per‑Note Pitch Bend  
- Flex Data (tempo, signature, metadata)

### ✓ **Schema Bridge (OpenAPI‑backed)**
- Converts runtime events ↔ structured schema packets  
- Guards auto‑generated from `midi2.full.openapi.json`  
- Single authoritative validation layer

### ✓ **SysEx7 & SysEx8 streaming**
- Fragmentation  
- Reassembly  
- CI Profiles, Properties, Discovery

### ✓ **Schedulers & Clocks**
- Browser monotonic clock  
- AudioContext‑aligned clock  
- Worker‑based clock  
- JR projection + jitter reduction  
- Deterministic event ordering

### ✓ **Host Adapters**
- WebAudio (poly synth stub)  
- Three.js (mesh spawning)  
- Cannon.js (rigid bodies)  

### ✓ **Record / Replay**
UMP capture and deterministic re‑playback using timestamp projections.

---

## 3. Quick Start

```ts
import {
  Midi2Scheduler,
  createBrowserClock,
  encodeNoteOn,
  decodeUmp,
  Midi2NoteOnEvent
} from "@fountain-coach/midi2";

const clock = createBrowserClock();
const scheduler = new Midi2Scheduler(clock);

scheduler.onEvent(evt => console.log("event:", evt));

const noteOn: Midi2NoteOnEvent = {
  kind: "noteOn",
  group: 0,
  channel: 0,
  note: 60,
  velocity: 50000,
};

scheduler.schedule(noteOn, clock.now() + 50);

const ump = encodeNoteOn(noteOn);
const decoded = decodeUmp(ump, clock.now());
console.log(decoded);
```

---

## 4. SysEx7 / SysEx8 Example

```ts
import { fragmentSysEx7, reassembleSysEx7 } from "@fountain-coach/midi2";

const packets = fragmentSysEx7([0x7D], [1, 2, 3, 4], 0);
const r = reassembleSysEx7(packets);
console.log(r.manufacturerId, r.payload);
```

---

## 5. WebAudio Adapter

```ts
import { createWebAudioAdapter } from "@fountain-coach/midi2";

const ctx = new AudioContext();
const audio = createWebAudioAdapter(ctx);

scheduler.onEvent(audio);
```

---

## 6. Scripts

```
npm run --prefix midi2.js build      # compile TS
npm run --prefix midi2.js check      # type-check only
npm run --prefix midi2.js codegen    # regenerate OpenAPI guards
npm run --prefix midi2.js test       # vitest
npm run --prefix midi2.js coverage   # vitest with coverage
npm run --prefix midi2.js clean      # remove dist/
```
`build` uses tsup to emit ESM + CJS bundles with type declarations into `dist/`.

---

## 7. Architecture Summary

MIDI 2.0 → UMP packets → clock projection → scheduler → adapters → (WebGPU / DSP / ML / Physics)

All timing-sensitive logic flows through the **JR timestamp projection engine**, ensuring deterministic ordering under browser jitter.

---

## 8. Vision

midi2.js aims to position MIDI 2.0 as the **browser’s first real-time orchestration layer**, enabling:

- deterministic WebGPU animation/compute  
- ML inference modulation  
- multi-agent systems  
- structured control UX  
- haptic & XR expression  
- cross-device synchronization  

MIDI 1.0 was about instruments.  
**MIDI 2.0 is about computation.**
