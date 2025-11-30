import { MidiCiEvent, SysEx7Event, SysEx8Event } from "./types";
import { fragmentSysEx7, fragmentSysEx8 } from "./sysex";

const MIDI_CI_SUB_ID1 = 0x0d;

function scopeByte(scope: MidiCiEvent["scope"]): number {
  return scope === "realtime" ? 0x7f : 0x7e;
}

/**
 * Encodes a MIDI-CI envelope into SysEx7 or SysEx8 UMP packet words.
 * Uses the universal non-realtime (0x7E) or realtime (0x7F) manufacturer ID.
 */
export function encodeMidiCiEvent(event: MidiCiEvent): Uint32Array[] {
  const scope = scopeByte(event.scope);
  const header =
    event.format === "sysex7"
      ? Uint8Array.from([scope, MIDI_CI_SUB_ID1, event.subId2 & 0x7f, event.version & 0x7f])
      : Uint8Array.from([scope, MIDI_CI_SUB_ID1, event.subId2, event.version]);
  const payload = new Uint8Array(header.length + event.payload.length);
  payload.set(header, 0);
  payload.set(event.payload, header.length);
  return event.format === "sysex7"
    ? fragmentSysEx7([scope], payload, event.group)
    : fragmentSysEx8([scope], payload, event.group);
}

/**
 * Decodes a SysEx7/SysEx8 event into a MIDI-CI envelope if it matches the expected structure.
 */
export function decodeMidiCiFromSysEx(event: SysEx7Event | SysEx8Event): MidiCiEvent | null {
  if (event.manufacturerId.length !== 1) {
    return null;
  }
  const mfg = event.manufacturerId[0];
  if (mfg !== 0x7e && mfg !== 0x7f) {
    return null;
  }
  const data = event.payload;
  if (data.length < 4) {
    return null;
  }
  if (data[0] !== mfg || data[1] !== MIDI_CI_SUB_ID1) {
    return null;
  }
  const scope = mfg === 0x7f ? "realtime" : "nonRealtime";
  const format = event.kind === "sysex7" ? "sysex7" : "sysex8";
  const subId2 = format === "sysex7" ? data[2] & 0x7f : data[2];
  const version = format === "sysex7" ? data[3] & 0x7f : data[3];
  const payload = data.slice(4);
  return {
    kind: "midiCi",
    group: event.group,
    scope,
    subId2,
    version,
    payload,
    format,
    timestamp: event.timestamp,
  };
}
