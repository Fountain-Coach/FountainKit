# FountainCoach/midi2 — Docs Agent Guide

What: This file is the single place to track the midi2.js Definition of Done and the remaining hardening tasks. Keep it in sync when status changes; do not spread checklists elsewhere.

Why: Avoid drift between the DoD (`docs/midi2-js-dod.md`), PB-VRT goldens (`docs/pb-vrt/*`), and the implementation plan in `agent.md`.

DoD (must be green in automated checks)
- UMP encode/decode: all MIDI 2.0 message types (Channel Voice, System Common/Real-Time, SysEx7/8, Flex, JR, Stream MT=0xF), MIDI 1.0 CV, per-note management/controllers, RPN/NRPN (abs/rel), validation of ranges/reserved bits.
- MIDI-CI: discovery, profiles (enable/disable/inquiry/reports/PSD), property exchange (chunked set/get/notify, compression/error codes), process inquiry (cap/message report), ACK/NAK.
- Scheduling/adapters: scheduler with browser/AudioContext/worker clocks; WebAudio/Three.js/Cannon.js adapters present and optional.
- Tooling/API: public API documented; pure core (no DOM), adapters thin; ESM + d.ts outputs.
- Testing/CI: unit tests for all encoders/decoders, SysEx fragmentation, MIDI-CI flows (profiles/PE/PI) with chunking; PB-VRT goldens exercised; CI runs codegen + check + tests.
- Examples: minimal WebAudio/Three.js/Cannon.js demos and SysEx/MIDI-CI snippets.
- Quality gates: no open TODOs for required spec items; changelog/releases current; dependencies free of known vulns that ship.

Active task matrix (implementation gaps to close)
1) Property Exchange
   - Enforce on decode/encode: command ∈ {capInquiry, capReply, get, getReply, set, setReply, subscribe, subscribeReply, notify, terminate}; requestId required for get/getReply/set/setReply/subscribe/subscribeReply/notify/terminate; encoding ∈ {json, binary, json+zlib, binary+zlib, mcoded7}; header must be object; data must be JSON object or Uint8Array; reject/downgrade otherwise.
   - Integrate chunk reassembly into decode: detect chunked set/notify/getReply with same command+requestId+encoding+header.res/total/offset/length; merge into one Uint8Array; set header.length; reject overlaps/missing/mismatch.
   - Add tests using docs/pb-vrt/property-exchange/set_chunked.json, notify_chunked.json, get_reply_chunked.json to assert merged payload bytes and headers; add negative tests for invalid command/encoding/header/data/requestId.
2) Profiles
   - Enforce: command ∈ {inquiry, reply, addedReport, removedReport, setOn, setOff, enabledReport, disabledReport, detailsInquiry, detailsReply, profileSpecificData}; profileId required for setOn/setOff/addedReport/removedReport/enabledReport/disabledReport/detailsInquiry/detailsReply/profileSpecificData; target required for setOn/setOff/detailsInquiry; channels required when target=channel; details must be object when present; reject/downgrade otherwise.
   - Add tests using docs/pb-vrt/profiles/enable_sequence.json, details_reply.json, enabled_report.json, disabled_report.json, profile_specific_data.json asserting decoded fields; add negative tests for missing/invalid profileId/target/channels/details.
3) Process Inquiry
   - Enforce: command ∈ {capInquiry, capReply, messageReport, messageReportReply, endReport}; filters must be object when present; reject/downgrade otherwise.
   - Add tests using docs/pb-vrt/process-inquiry/flows.json asserting decoded commands and filters; add negative tests for invalid commands/filters.
4) Negative/reserved checks
   - Add rejection tests for stream opcode=0x00 with non-zero payload; invalid PE commands/encoding/header/data/requestId; invalid profile commands/fields; invalid PI commands/filters. Ensure reserved bits enforced across stream opcodes.
5) Optional
   - Expose PE chunk aggregation as a public decode option once implemented.

How/Where
- DoD source of truth: `docs/midi2-js-dod.md`.
- Goldens: `docs/pb-vrt/*` (stream, JR, profiles, property-exchange, process-inquiry, sysex8/mds).
- Agent status: `agent.md` (keep “Gap to finish line” aligned with this file).
- When updating DoD or tasks, edit this file and `docs/midi2-js-dod.md` together.
