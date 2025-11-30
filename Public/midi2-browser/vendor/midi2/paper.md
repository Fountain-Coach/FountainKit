# MIDI 2.0 as a Real-Time Control Plane for WebGPU  
## A Technical Paper

---

## Abstract

This paper redefines MIDI 2.0 as a **general-purpose real-time control protocol** for heterogeneous browser compute: WebGPU, DSP graphs, ML inference engines, physics scenes, XR systems, and multi-agent architectures.  
While historically associated with musical instruments, MIDI 2.0 introduces data structures—32‑bit parameters, UMP packets, JR timestamps, structured SysEx envelopes, Profiles/Properties—that make it functionally equivalent to a **vendor‑agnostic micro-scheduler** for event-driven computation.

The `midi2.js` implementation demonstrates this new framing, providing a browser-native control fabric that integrates with WebGPU pipelines and worker‑based timing.

---

## 1. Introduction

Browsers now provide:
- **WebGPU** for general-purpose GPU compute  
- **WASM** for near‑native DSP and ML kernels  
- **WebAudio** for sample-rate processing  
- **Workers** for parallel timelines  

What they lack is a unified, timestamped event fabric that binds these subsystems into a coherent real-time environment.

MIDI 2.0 provides it.

---

## 2. MIDI 2.0: Beyond Musical Events

The retro association (“note on/off”) obscures the true design of MIDI 2.0.

MIDI 2.0 defines:
- Universal MIDI Packets (UMP) as machine-aligned 32/64‑bit words  
- timestamped scheduling (JR clock)  
- arbitrarily structured SysEx messaging (SysEx7/8)  
- device capability negotiation (Profiles/Properties)  
- high‑resolution per-parameter expression  

These characteristics match the needs of **real-time GPU/DSP systems**, not just digital instruments.

---

## 3. The Need for a Real-Time Control Plane

WebGPU intentionally exposes no real-time guarantees.  
DSP graphs and ML inference require deterministic event ordering.  
Workers drift.  
AudioContext clock is steady but isolated.

A unifying control mechanism must:

1. **timestamp events**  
2. **predictively project latency**  
3. **coalesce jitter**  
4. **provide structure and device negotiation**  
5. **operate across browser subsystems**

MIDI 2.0 provides all five.

---

## 4. UMP as a Packet Format for Compute Systems

A UMP word resembles:
- a GPU push-constant  
- a bind group update  
- a shader input lane  
- a ML model modulator  

UMP ordering rules guarantee:
- event-time monotonicity  
- lossless batching  
- multi-packet assembly  

SysEx7/8 introduces structured envelopes analogous to:
- ML configuration packets  
- GPU pipeline state messages  
- physics scene updates  

---

## 5. JR Timestamp Projection

The JR clock provides:
- **sub-millisecond timestamp precision**  
- **deterministic ordering during jitter**  
- **projection from worker clocks**  
- **alignment with AudioContext / performance.now()**

This is fundamentally a **general-purpose micro-scheduler**.

midi2.js implements JR projection, jitter windows, and coalescing.

---

## 6. Integration with WebGPU

MIDI 2.0 does not submit GPU commands.  
It **schedules the logic that produces them.**

Use cases:
- drive animation curves  
- parameterize compute shaders  
- synchronize multi-agent simulations  
- modulate neural network inputs  
- control particle systems and physics bodies  
- manage shader graph transitions  

MIDI 2.0 becomes the **semantic expression layer** for WebGPU.

---

## 7. DSP, ML, and Physics

### DSP  
Per-note controllers and high-res parameters map directly to:
- filter parameters  
- FM operators  
- wavetable morphing  
- granular envelopes  

### ML  
SysEx7/8 (schema-bound) becomes:
- model selection packet  
- inference parameter lane  
- embedding adjustments  

### Physics  
UMP streams schedule:
- rigid body impulses  
- scene graph mutations  
- spawn/despawn events  

---

## 8. Browser Architecture with midi2.js

```
     +-------------------+
     |   Application     |
     +---------+---------+
               |
               v
     +-------------------+
     |   midi2.js API    |
     +---------+---------+
               |
    +----------+------------+
    | Schedulers & Clocks   |
    | JR Projection Engine  |
    +----------+------------+
               |
    +----------+------------+
    |  UMP Encode/Decode    |
    |  SysEx7/8 Envelope    |
    |  Profiles/Properties  |
    +----------+------------+
               |
    +----------+------------+
    |   Host Adapters       |
    |  WebGPU / DSP / ML    |
    |   WebAudio / XR       |
    +------------------------+
```

---

## 9. Conclusion

MIDI 2.0 is not a music protocol.  
It is a **real-time compute control plane** that the browser has been missing for decades.

`midi2.js` implements this modern interpretation:  
**a unified timing, structure, and negotiation layer for heterogeneous computation.**

