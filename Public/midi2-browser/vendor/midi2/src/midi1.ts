import { fragmentSysEx7 } from "./sysex";
import { encodeUmp } from "./ump";
import { Midi2Event, Midi2NoteOffEvent, Midi2NoteOnEvent, Midi2PitchBendEvent, Midi2ProgramChangeEvent, Midi2SystemEvent, MidiCiEvent, SysEx7Event } from "./types";

function isChannelVoiceStatus(status: number): boolean {
  return status >= 0x80 && status <= 0xef;
}

function channelDataLength(status: number): number {
  const upper = status & 0xf0;
  if (upper === 0xc0 || upper === 0xd0) return 1;
  return 2;
}

function isRealtimeStatus(status: number): boolean {
  return status >= 0xf8 && status <= 0xff && status !== 0xf9 && status !== 0xfd;
}

function assertDataByte(value: number): void {
  if (!Number.isInteger(value) || value < 0 || value > 0x7f) {
    throw new RangeError(`Invalid MIDI 1.0 data byte: ${value}`);
  }
}

function assertSystemStatus(status: number): void {
  const valid = [0xf1, 0xf2, 0xf3, 0xf6];
  if (!valid.includes(status)) {
    throw new RangeError(`Unsupported system common status 0x${status.toString(16)}`);
  }
}

function systemCommonLength(status: number): number {
  switch (status) {
    case 0xf1: // MTC Quarter Frame
      return 1;
    case 0xf2: // Song Position Pointer
      return 2;
    case 0xf3: // Song Select
      return 1;
    case 0xf6: // Tune Request
      return 0;
    default:
      throw new RangeError(`Unsupported system common status 0x${status.toString(16)}`);
  }
}

const SYSTEM_STATUSES: Midi2SystemEvent["status"][] = [0xf1, 0xf2, 0xf3, 0xf6, 0xf8, 0xfa, 0xfb, 0xfc, 0xfe, 0xff];

function toSystemStatus(value: number): Midi2SystemEvent["status"] {
  const status = value & 0xff;
  const typed = status as Midi2SystemEvent["status"];
  if (!SYSTEM_STATUSES.includes(typed)) {
    throw new RangeError(`Unsupported system status 0x${status.toString(16)}`);
  }
  return typed;
}

function parseSysEx(data: number[], start: number, group: number, out: Uint32Array[]): number {
  const payload: number[] = [];
  for (let i = start + 1; i < data.length; i++) {
    const b = data[i];
    if (b === 0xf7) {
      if (payload.length === 0) {
        throw new RangeError("SysEx payload is empty.");
      }
      const manufacturerId = payload[0] === 0x00 ? payload.slice(0, 3) : [payload[0]];
      if (manufacturerId.length !== 1 && manufacturerId.length !== 3) {
        throw new RangeError("SysEx manufacturer ID must be 1 or 3 bytes.");
      }
      const message = payload.slice(manufacturerId.length);
      out.push(...fragmentSysEx7(manufacturerId, message, group));
      return i + 1;
    }
    if (isRealtimeStatus(b)) {
      out.push(encodeUmp({ kind: "system", group, status: toSystemStatus(b) }));
      continue;
    }
    payload.push(b);
  }
  throw new RangeError("Unterminated SysEx message (missing 0xF7).");
}

function scale16To7(value: number): number {
  return Math.max(0, Math.min(0x7f, Math.round((value / 0xffff) * 0x7f)));
}

function scale32To14(value: number): number {
  const clamped = Math.max(0, Math.min(0xffffffff, value >>> 0));
  return Math.round((clamped / 0xffffffff) * 0x3fff);
}

/**
 * Converts a MIDI 1.0 byte stream (with optional running status) into UMP packets.
 * Supports channel voice, system common (0xF1/0xF2/0xF3/0xF6), and real-time messages.
 * Handles SysEx7 (0xF0 ... 0xF7) with 1- or 3-byte manufacturer IDs; real-time bytes interleaved in SysEx are emitted separately.
 */
export function midi1BytesToUmp(bytes: ArrayLike<number>, group = 0): Uint32Array[] {
  const data = Array.from(bytes, b => b & 0xff);
  const out: Uint32Array[] = [];
  let runningStatus: number | null = null;

  let i = 0;
  while (i < data.length) {
    const byte = data[i];
    if (byte & 0x80) {
      if (isRealtimeStatus(byte)) {
        const evt: Midi2Event = { kind: "system", group, status: toSystemStatus(byte) };
        out.push(encodeUmp(evt));
        i += 1;
        continue;
      }
      if (isChannelVoiceStatus(byte)) {
        const len = channelDataLength(byte);
        if (i + len >= data.length) throw new RangeError("Incomplete MIDI 1.0 channel voice message.");
        const d1 = data[i + 1];
        assertDataByte(d1);
        const d2 = len === 2 ? data[i + 2] : undefined;
        if (len === 2) assertDataByte(d2!);
        const evt: Midi2Event = { kind: "midi1ChannelVoice", group, status: byte, data1: d1, data2: d2 };
        out.push(encodeUmp(evt));
        runningStatus = byte;
        i += 1 + len;
        continue;
      }
      if (byte === 0xf0) {
        runningStatus = null;
        i = parseSysEx(data, i, group, out);
        continue;
      }
      if (byte === 0xf7) {
        throw new RangeError("Unexpected SysEx end (0xF7) without start.");
      }
      assertSystemStatus(byte);
      const len = systemCommonLength(byte);
      if (i + len >= data.length) throw new RangeError("Incomplete MIDI 1.0 system common message.");
      const d1 = len >= 1 ? data[i + 1] : undefined;
      const d2 = len === 2 ? data[i + 2] : undefined;
      if (d1 !== undefined) assertDataByte(d1);
      if (d2 !== undefined) assertDataByte(d2);
      const evt: Midi2Event = { kind: "system", group, status: toSystemStatus(byte), data1: d1, data2: d2 };
      out.push(encodeUmp(evt));
      runningStatus = null; // system common breaks running status
      i += 1 + len;
      continue;
    }

    if (runningStatus === null) {
      throw new RangeError("Data byte encountered without running status.");
    }
    const len = channelDataLength(runningStatus);
    if (len === 1) {
      assertDataByte(byte);
      const evt: Midi2Event = { kind: "midi1ChannelVoice", group, status: runningStatus, data1: byte };
      out.push(encodeUmp(evt));
      i += 1;
      continue;
    }
    if (i + 1 >= data.length) {
      throw new RangeError("Incomplete running-status message.");
    }
    const d1 = byte;
    const d2 = data[i + 1];
    assertDataByte(d1);
    assertDataByte(d2);
    const evt: Midi2Event = { kind: "midi1ChannelVoice", group, status: runningStatus, data1: d1, data2: d2 };
    out.push(encodeUmp(evt));
    i += 2;
  }

  return out;
}

/**
 * Down-converts a subset of MIDI 2.0 channel voice events to MIDI 1.0 bytes.
 * Note/velocity and pressure values are scaled to 7-bit; pitch bend is scaled to 14-bit.
 */
export function midi2ChannelVoiceToMidi1Bytes(event: Midi2Event): number[] {
  switch (event.kind) {
    case "noteOn": {
      const e = event as Midi2NoteOnEvent;
      const status = 0x90 | (e.channel & 0x0f);
      const velocity = scale16To7(e.velocity);
      return [status, e.note & 0x7f, velocity];
    }
    case "noteOff": {
      const e = event as Midi2NoteOffEvent;
      const status = 0x80 | (e.channel & 0x0f);
      const velocity = scale16To7(e.velocity ?? 0);
      return [status, e.note & 0x7f, velocity];
    }
    case "controlChange": {
      const status = 0xb0 | (event.channel & 0x0f);
      const value = scale32To14(event.value) & 0x7f;
      return [status, event.controller & 0x7f, value];
    }
    case "programChange": {
      const e = event as Midi2ProgramChangeEvent;
      const status = 0xc0 | (e.channel & 0x0f);
      const bytes: number[] = [];
      if (e.bankMsb !== undefined) {
        bytes.push(0xb0 | (e.channel & 0x0f), 0x00, e.bankMsb & 0x7f);
      }
      if (e.bankLsb !== undefined) {
        bytes.push(0xb0 | (e.channel & 0x0f), 0x20, e.bankLsb & 0x7f);
      }
      bytes.push(status, e.program & 0x7f);
      return bytes;
    }
    case "channelPressure": {
      const status = 0xd0 | (event.channel & 0x0f);
      const value = scale32To14(event.pressure) & 0x7f;
      return [status, value];
    }
    case "pitchBend": {
      const e = event as Midi2PitchBendEvent;
      const status = 0xe0 | (e.channel & 0x0f);
      const bend14 = scale32To14(e.value);
      const lsb = bend14 & 0x7f;
      const msb = (bend14 >> 7) & 0x7f;
      return [status, lsb, msb];
    }
    default:
      throw new RangeError(`Unsupported MIDI 2.0 event kind for down-conversion: ${(event as Midi2Event).kind}`);
  }
}

function sysexBytesFromEvent(evt: SysEx7Event): number[] {
  const header = evt.manufacturerId.map(b => b & 0x7f);
  const payload = Array.from(evt.payload, b => b & 0x7f);
  return [0xf0, ...header, ...payload, 0xf7];
}

function sysexFromMidiCi(event: MidiCiEvent): number[] {
  const scopeByte = event.scope === "realtime" ? 0x7f : 0x7e;
  const subId2 = event.format === "sysex7" ? event.subId2 & 0x7f : event.subId2;
  const version = event.format === "sysex7" ? event.version & 0x7f : event.version;
  const payload = [0x0d, subId2, version, ...Array.from(event.payload, b => b & 0x7f)];
  if (payload.length > 0xffff) {
    throw new RangeError("MIDI-CI SysEx payload too long for MIDI 1.0 framing.");
  }
  const sysEx: SysEx7Event = {
    kind: "sysex7",
    group: event.group,
    manufacturerId: [scopeByte],
    payload: Uint8Array.from(payload),
  };
  return sysexBytesFromEvent(sysEx);
}

/**
 * Down-converts MIDI 2.0/1.0 events to a MIDI 1.0 byte stream.
 * Applies running status for channel voice messages when enabled; system/common and SysEx reset running status.
 */
export function midi2EventsToMidi1Bytes(events: Midi2Event[], opts?: { runningStatus?: boolean; includeTimestamps?: boolean }): number[] {
  const running = opts?.runningStatus ?? true;
  let lastStatus: number | null = null;
  const out: number[] = [];

  const emitStatusData = (status: number, data: number[]): void => {
    if (running && lastStatus === status && (status & 0xf0) !== 0xc0 && (status & 0xf0) !== 0xd0) {
      out.push(...data);
    } else {
      out.push(status, ...data);
      if (status >= 0x80 && status <= 0xef) {
        lastStatus = status;
      }
    }
  };

  for (const evt of events) {
    switch (evt.kind) {
      case "midi1ChannelVoice": {
        const status = evt.status & 0xff;
        const d1 = evt.data1 ?? 0;
        const d2 = evt.data2;
        if (status >= 0xc0 && status <= 0xdf) {
          emitStatusData(status, [d1 & 0x7f]);
        } else {
          emitStatusData(status, [d1 & 0x7f, (d2 ?? 0) & 0x7f]);
        }
        break;
      }
      case "noteOn":
      case "noteOff":
      case "controlChange":
      case "programChange":
      case "channelPressure":
      case "pitchBend": {
        const bytes = midi2ChannelVoiceToMidi1Bytes(evt);
        const status = bytes[0];
        emitStatusData(status, bytes.slice(1));
        break;
      }
      case "system": {
        const status = evt.status & 0xff;
        const parts: number[] = [status];
        if (evt.data1 !== undefined) parts.push(evt.data1 & 0x7f);
        if (evt.data2 !== undefined) parts.push(evt.data2 & 0x7f);
        out.push(...parts);
        lastStatus = null;
        break;
      }
      case "sysex7": {
        const sys = evt as SysEx7Event;
        out.push(0xf0, ...sys.manufacturerId, ...sys.payload, 0xf7);
        lastStatus = null;
        break;
      }
      case "sysex8": {
        const bytes = sysexBytesFromEvent({
          kind: "sysex7",
          group: evt.group,
          manufacturerId: evt.manufacturerId,
          payload: Uint8Array.from(evt.payload, b => b & 0x7f),
        });
        out.push(...bytes);
        lastStatus = null;
        break;
      }
      case "midiCi": {
        const bytes = sysexFromMidiCi(evt);
        out.push(...bytes);
        lastStatus = null;
        break;
      }
      default:
        // Unsupported event types are skipped in this down-conversion.
        lastStatus = null;
        break;
    }
  }

  return out;
}
