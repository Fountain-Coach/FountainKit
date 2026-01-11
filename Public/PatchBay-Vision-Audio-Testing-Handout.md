# PatchBay, Now With Vision + Audio Confidence

A short, non‑technical overview of how PatchBay’s new testing powers keep screens and sounds consistent, fast, and reliable — even as we move quickly.

## Why It Matters

- Fewer surprises: Visuals and audio behave the same across builds.
- Faster reviews: Clear, automatic pass/fail with helpful pictures and clips.
- Safer changes: Designers and engineers can iterate without breaking core feel.

## What PatchBay Is

PatchBay is our visual “instrument bay” — a canvas where instruments (editor, memory, tools) connect and perform. It’s interactive, MIDI 2.0‑aware, and powers our editing and composer flows.

## What We Added

We extended PatchBay with two families of automatic checks:

- Vision checks (for screens)
  - Spots meaningful visual changes, not just pixel noise.
  - Understands page layout (A4), margins, and text wrapping.
  - Aligns before comparing, so small shifts don’t cause false alarms.
- Audio checks (for sound)
  - Listens to recordings and compares “what it is” (embeddings) and “how it looks” as a spectrogram.
  - Tracks timing (onsets/tempo), pitch (notes), and loudness over time.
  - Can measure sync with MIDI events (was a sound late or early?).

## How It Works (In Plain Language)

- One clear description (a “prompt”) tells PatchBay what the screen or sound should be.
- We save a reference snapshot (a “baseline”) for that prompt.
- Every time we build, PatchBay repeats the same steps and compares the result to the baseline.
- If something important changed, the check fails with a short report and evidence.

## What You See In Reports

- Visual highlights: areas that changed, with simple labels like “text re‑wrapped” or “page margins shifted”.
- Audio deltas: a chart of sound differences, timing offsets, and pitch drift.
- A single verdict: pass or fail, with a short reason.
- Links to evidence: images, overlays, small JSON summaries, and (optionally) audio clips.

## What We Check (Without The Jargon)

- For screens
  - Content first: Focuses on the parts people look at; ignores harmless background noise.
  - Layout rules: A4 size, margins, number of lines, and wrapping stay within bounds.
  - Gentle camera: Small pans/zooms don’t confuse the checker; we align first.
- For sound
  - “Same meaning”: Two sounds that feel the same pass, even if recorded again.
  - Rhythm & pitch: Beats land where they should; notes stay in tune within tolerance.
  - Volume & shape: Loudness over time looks right; no unexpected spikes.

## Who Benefits

- Designers: Catch unintended layout or spacing drift early.
- Writers/Composers: Keep the “typewriter feel” and page rhythm consistent; verify audio cues.
- QA/Release: One button to validate visuals and audio; clear artifacts for tickets.

## Everyday Use

- Make a change → build → the checks run automatically.
- If anything important changed, you’ll see a short report with pictures/clips.
- Agree it should change? Update the baseline with one command.
- Otherwise, fix and re‑run. No guesswork.

## Privacy & Storage

- No secrets in these artifacts. Snapshots and small JSON files live under the project’s `.fountain/` folder.
- We keep one “source of truth” page per topic in our internal FountainStore, so anyone can find the latest rules.

## Where To Learn More

- Internal doc (for product teams): “FCIS-VRT Render — Vision + Audio Probes (Spec & Plan)”
  - Stored in FountainStore: corpus `patchbay`, page `docs:pb-vrt-vision-audio` (legacy id).
- Ask the team if you want a quick demo — the reports make it click in a minute.

---

Short version: we turned PatchBay’s eyes and ears on. It now notices the changes humans notice — and helps us keep the good parts steady while we ship faster.
