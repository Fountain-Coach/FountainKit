# From Views to Instruments — and the Little Linter That Keeps Us Honest

> “It runs on my machine” is not good enough when your UI is supposed to be an instrument in an orchestra.

This story is about a very particular world: FountainKit, where a GUI surface is treated as a **MIDI 2.0 instrument**, not just a view. If you are used to thinking in buttons and view controllers, some of the words here will be new. That’s intentional.

Before we talk about the linter, we need a few pieces of vocabulary:

- `FountainKit` — this repository; a Swift workspace for building and testing MIDI‑driven instruments.
- **Instrument** — a GUI surface that can be driven and observed over MIDI 2.0 Property Exchange (PE).
- **Teatro prompt** — a human‑written description of a surface, stored in FountainStore under `prompt:<app-id>`. Think “stage directions” in plain language.
- **OpenAPI spec** — a machine‑readable contract for an HTTP API in `Packages/FountainSpecCuration/openapi/v1/*.yml`.
- **Facts** — Property Exchange metadata generated from an OpenAPI spec and stored in FountainStore; this tells the MIDI host how to call an instrument’s HTTP routes.
- **PB‑VRT** — PatchBay Visual Regression Tests; image‑based tests that compare rendered frames against baselines.
- **MRTS** — MIDI Robot Test Scripts; tests that drive instruments by sending MIDI 2.0 UMP and checking numeric and visual invariants.

What follows is not “common sense UI advice”. It’s a concrete story about how one codebase repeatedly shipped beautiful *views* that were not real *instruments*—and how a small, grumpy tool called `instrument-lint` helped us stop doing that.

---

## 1. Why Instruments Keep Failing Quietly

In this world, we keep running into the same failure mode:

- Someone builds a gorgeous demo: a Metal canvas, a square that glides under your fingers, maybe zoom, maybe rotation.
- It behaves perfectly under their hand, on their machine.
- And yet nothing else in the system can meaningfully talk to it.

There is no MIDI 2.0 route into it, no facts in FountainStore, no OpenAPI spec for its state, no PB‑VRT baselines to catch visual drift. It is a sealed box.

In an ordinary GUI app that might be acceptable. In FountainKit — where the whole point is to treat GUIs as MIDI instruments you can drive and test robotically — it is a structural bug. You get a museum of demos instead of a band of instruments.

Stopping that pattern required us to say, out loud, what “instrument” means here.

---

## 2. What We Mean by an Instrument

Most GUI frameworks encourage you to think in views: rectangles that can draw, respond to events, maybe animate. They are cheap and disposable.

FountainKit deliberately uses a different word. We talk about **instruments**.

An instrument is closer to a stage prop in a theatre than a widget in a toolbox. In our system it has:

- a name and an identity (`PatchBay Canvas`, `MPE Pad`, `FountainGUI Demo Canvas`);
- a set of knobs and levers (properties) that can be pulled in predictable ways;
- and a quiet promise that if you push it the same way twice, it will behave the same way twice.

Under the hood that promise is backed by concrete plumbing:

- MIDI 2.0 Property Exchange fields that carry the instrument’s knobs as structured data.
- OpenAPI specs and generated types that describe how to reach those knobs over HTTP.
- Facts in FountainStore so the MIDI host can route PE GET/SET calls to the right HTTP operations.
- Tests (including PB‑VRT and MRTS where possible) that drive both properties and pixels.

The picture to hold in mind is simple: if you put this thing on stage, a human performer, a MIDI robot, and a conductor AI should all be able to read its sheet music and make it behave. If that is not true, it is not yet an instrument, no matter how pretty the shader.

---

## 3. The Invisible Paperwork: Prompts, Specs, Facts, Tests

Every instrument in FountainKit is supposed to leave a small paper trail behind it. When you are in the middle of exploring an idea on a canvas, it is easy to forget that trail exists.

If you zoom out from the code, you can see four “shadows” following each instrument:

### 3.1 The prompt — stage directions

Somewhere, a human writes down “this is what the thing does.” In FountainKit we make that explicit: a **Teatro prompt** stored in FountainStore. It is a chunk of plain text under a key like `prompt:fountain-gui-demo:teatro`.

For example, the prompt for a canvas instrument might say:

- A 640×400 window.
- A blue square that can pan, zoom, and rotate about the center.
- Trackpad drag and scroll pan the square (follow‑finger).
- Pinch zooms between 0.2 and 5.0.
- Rotate gesture adjusts rotation between −2π and 2π.

This is the **playbill blurb** for the instrument: where it sits, what it controls, how it is supposed to feel under a hand or a trackpad.

### 3.2 The spec — the conductor’s score

Next to the prompt lives an **OpenAPI document** in `Packages/FountainSpecCuration/openapi/v1`. That is the contract the rest of the system sees: HTTP routes, JSON schemas, error codes.

For a visual instrument you might have a spec called `fountain-gui-demo.yml` with routes like:

- `GET /canvas/state` returning `canvas.zoom`, `canvas.translation.x/y`, `canvas.rotation`.
- `POST /canvas/set` accepting the same fields.

This is the **conductor’s score** — precise, unforgiving, no anecdotes allowed.

### 3.3 The facts — wiring diagram

**Facts** are the link between “playbill” and “score”: Property Exchange metadata generated from the spec and stored in FountainStore (in the `agent-facts` collection). They tell the MIDI host exactly which property name maps to which HTTP route and which body shape.

They answer questions like:

- “When I set `canvas.zoom` via PE, which HTTP path and method should I use?”
- “What does a sample request body look like?”

This is the **stage manager’s clipboard**: which lever talks to which cable, which operation is writable, which ones are tools‑only.

### 3.4 The tests — rehearsal footage

Finally, there are tests:

- unit tests that poke properties directly and assert invariants;
- PB‑VRT snapshot tests that compare pixels against baselines for visual drift;
- MIDI robot tests (MRTS) that stream UMP and assert the transform behaves (follow‑finger pan, anchor‑stable zoom).

This is your **rehearsal footage**: evidence that the show looks like the poster and that it still looks like the poster after you refactor.

When an instrument feels “off” it’s rarely because the square doesn’t move under your finger. It’s because one of these four shadows is missing, stale, or inconsistent. The demo looks fine, but there’s no prompt; the spec exists, but facts aren’t seeded; there are tests in a different module that never run for this target.

We needed a way to stop lying to ourselves about those shadows, especially when the interactive demo felt perfectly “done” on the developer’s laptop.

---

## 4. instrument‑lint: A Tiny Tool With Sharp Teeth

On paper, `instrument-lint` is unassuming: an executable in `Packages/FountainTooling` that reads some JSON, pokes some files, and emits a few lines to stderr.

In practice, it behaves like a grumpy stage manager who has seen too many half‑wired props.

It takes a single input: `Tools/instruments.json`, our small census of instruments. For each entry it asks a series of yes/no questions:

- **Spec**  
  “Does your spec file actually exist under `Packages/FountainSpecCuration/openapi/v1/<spec>`?”

- **Mapping**  
  “Did you remember to wire this agent into `Scripts/openapi/openapi-to-facts.sh` so PE facts will be generated?”

- **Facts**  
  “Is there a facts document in FountainStore for this `agentId` (`facts:agent:<id>`), or are we pretending?”

- **Tests**  
  “Where do your tests live? Does `testModulePath` exist? Does it contain any `.swift` files at all?”

- **Named test classes**  
  “You claimed you have `FountainGUIDemoTests` and `FountainGUIDemoSnapshotTests`. Do those symbols actually appear in your test sources?”

- **Snapshots (optional)**  
  “If you say you have snapshot baselines, did you at least create a directory for them?”

If any of those answers is **no**, `instrument-lint` does not debate or warn. It prints a short, specific complaint and exits non‑zero so CI can fail loudly.

It does not care how clever the demo is or how pretty the shader looks. If you have put an instrument in the index and you have not:

- given it a spec,
- mapped that spec to facts,
- and written tests where you said you would,

then `instrument-lint` will drag it back out of the spotlight.

That is the point: it is a small tool that encodes a strong opinion — that instruments are not allowed to be half‑finished.

---

## 5. Making instrument‑lint a First‑Class Fountain Citizen

We did not want `instrument-lint` to live as a local script you have to remember. In FountainKit, important things get specs, facts, and agents.

So we gave it the same treatment as everything else:

- An **OpenAPI 3.1 spec**: `Packages/FountainSpecCuration/openapi/v1/instrument-lint.yml`.
  - `GET /instruments` returns the instrument index as JSON.
  - `POST /lint/run` accepts an optional list of `appIds` and returns `{ ok, results[] }` with per‑instrument messages.

- A **tool agent id**: `fountain.coach/agent/instrument-lint/service`.

- A mapping in `Scripts/openapi/openapi-to-facts.sh` so PE facts are generated and stored in the `agents` corpus.

Why does this matter? Because now `instrument-lint` is visible to the rest of the system:

- Tools Factory and Gateway can treat it as a **tool agent**.
- LLMs can call `runLint` over HTTP instead of shelling out.
- Other services can inspect the instrument catalogue via `GET /instruments` without scraping files.

In other words, the thing that judges instruments is itself a first‑class instrument in the ecosystem — fully described, testable, and callable.

---

## 6. The Human × LLM Instrument Workflow

Once you have a linter with teeth and a language the tools can speak, the human–LLM workflow changes shape.

It stops being:

> “I added a new NSView; I think it’s an instrument now?”

and starts looking more like a small ensemble where everyone knows their part.

### 6.1 The conversation

A typical flow might sound like this:

> **Human:** “I want a new instrument called `Orbit Canvas`. It should pan and zoom like PatchBay but only rotate in 90° snaps.”  
>  
> **LLM:** “Got it. I’ll do four things:
>  1. Draft the Teatro prompt that describes Orbit Canvas.
>  2. Add an entry to the instrument index.
>  3. Create an OpenAPI spec and facts.
>  4. Stub tests and then ask the linter what I missed.”

Behind the scenes the LLM:

- Writes a seeder that puts `prompt:orbit-canvas:teatro` and `:facts` into FountainStore.
- Adds an entry to `Tools/instruments.json` with:
  - `appId="orbit-canvas"`,
  - `agentId="fountain.coach/agent/orbit-canvas/service"`,
  - `spec="orbit-canvas.yml"`,
  - `testModulePath="Packages/FountainApps/Tests/OrbitCanvasTests"`,
  - `requiredTestSymbols=["OrbitCanvasTests", "OrbitCanvasSnapshotTests"]`.
- Creates `openapi/v1/orbit-canvas.yml` with routes that match the prompt.
- Registers the spec in `openapi-to-facts.sh`, then runs `openapi-to-facts` to seed PE facts.
- Stubs `OrbitCanvasTests` + `OrbitCanvasSnapshotTests` in a proper test module.

Then it calls `instrument-lint` (either via the CLI or `POST /lint/run`) and reads back the complaints:

- “Spec missing.”  
- “Facts missing.”  
- “Test module folder exists but required symbol `OrbitCanvasSnapshotTests` not found.”

And it iterates — patching code, spec, and index — until `instrument-lint` reports `ok: true` for `orbit-canvas`.

Only then does it come back to the human and say:

> “Here’s the prompt, here are the tests, here’s the spec. The instrumentation checks out. Now let’s talk about feel.”

The human’s job shrinks to the parts humans are good at:

- Describing the surface in Teatro.  
- Judging the UX and aesthetics.  
- Deciding which invariants actually matter.

The LLM + linter combo takes care of:

- Remembering the invisible paperwork.  
- Wiring specs and facts.  
- Ensuring there is at least one unit test and one snapshot/PB‑VRT‑style test for each instrument in the index.

### 6.2 Onboarding without a map

This matters most when someone new joins the project.

Without this flow, you have to know which documents to read and which scripts to run, in the right order, just to add a new instrument. That’s brittle.

With `Design/INSTRUMENT_REQUIREMENTS.md`, `Tools/instruments.json`, and `instrument-lint` in place, the recipe is shorter:

1. Tell Codex: “Add a new instrument named `<name>` and wire it properly.”
2. Let the LLM:
   - Propose the prompt, spec, index entry, seeder, and tests.
   - Run `instrument-lint` and fix whatever it complains about.
3. As a human, you only review:
   - The Teatro prompt (does it describe what you want?).
   - The behaviour (does it feel right under hand and in tests?).

The rest becomes a mechanical contract the system can enforce — by design, not by heroic memory.

---

In the end, `instrument-lint` is just a small tool in a big codebase. But by giving it a spec, an agent id, and sharp enough rules to say “no”, it changes the default outcome from “maybe this is an instrument” to “prove it.” And that’s exactly the kind of grumpy stage manager a complex, instrument‑driven system needs. 
