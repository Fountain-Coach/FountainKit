import { describe, expect, it } from "vitest";
import { midi1BytesToUmp, midi2ChannelVoiceToMidi1Bytes, midi2EventsToMidi1Bytes } from "../midi1";
import { decodeUmp } from "../ump";
import { reassembleSysEx7 } from "../sysex";
import { Midi2Event } from "../types";

describe("midi1BytesToUmp", () => {
  it("decodes channel voice with running status", () => {
    const packets = midi1BytesToUmp([0x90, 0x3c, 0x40, 0x3e, 0x41], 1);
    expect(packets).toHaveLength(2);
    const events = packets.map(p => decodeUmp(p));
    expect(events[0]).toMatchObject({ kind: "midi1ChannelVoice", group: 1, status: 0x90, data1: 0x3c, data2: 0x40 });
    expect(events[1]).toMatchObject({ kind: "midi1ChannelVoice", group: 1, status: 0x90, data1: 0x3e, data2: 0x41 });
  });

  it("supports program change running status (single data byte)", () => {
    const packets = midi1BytesToUmp([0xc2, 0x05, 0x06]);
    expect(packets).toHaveLength(2);
    const events = packets.map(p => decodeUmp(p));
    expect(events[0]).toMatchObject({ kind: "midi1ChannelVoice", status: 0xc2, data1: 0x05, data2: undefined });
    expect(events[1]).toMatchObject({ kind: "midi1ChannelVoice", status: 0xc2, data1: 0x06, data2: undefined });
  });

  it("handles interleaved real-time without breaking running status", () => {
    const packets = midi1BytesToUmp([0x90, 0x30, 0x20, 0xf8, 0x32, 0x21]);
    expect(packets).toHaveLength(3);
    const events = packets.map(p => decodeUmp(p));
    expect(events[0]).toMatchObject({ kind: "midi1ChannelVoice", status: 0x90, data1: 0x30, data2: 0x20 });
    expect(events[1]).toMatchObject({ kind: "system", status: 0xf8 });
    expect(events[2]).toMatchObject({ kind: "midi1ChannelVoice", status: 0x90, data1: 0x32, data2: 0x21 });
  });

  it("parses system common messages and clears running status", () => {
    const packets = midi1BytesToUmp([0xf2, 0x01, 0x02, 0xf3, 0x05]);
    expect(packets).toHaveLength(2);
    const events = packets.map(p => decodeUmp(p));
    expect(events[0]).toMatchObject({ kind: "system", status: 0xf2, data1: 0x01, data2: 0x02 });
    expect(events[1]).toMatchObject({ kind: "system", status: 0xf3, data1: 0x05, data2: undefined });
  });

  it("throws on data bytes without running status", () => {
    expect(() => midi1BytesToUmp([0x40, 0x41])).toThrow(RangeError);
  });

  it("throws on incomplete channel voice message", () => {
    expect(() => midi1BytesToUmp([0x90, 0x3c])).toThrow(RangeError);
  });

  it("throws on unsupported SysEx statuses", () => {
    expect(() => midi1BytesToUmp([0xf7])).toThrow(RangeError);
  });

  it("parses SysEx7 with manufacturer id and payload", () => {
    const bytes = [0xf0, 0x00, 0x20, 0x33, 0x01, 0x02, 0x03, 0xf7];
    const packets = midi1BytesToUmp(bytes, 2);
    expect(packets.length).toBeGreaterThanOrEqual(1);
    const msg = reassembleSysEx7(packets);
    expect(msg.group).toBe(2);
    expect(msg.manufacturerId).toEqual([0x00, 0x20, 0x33]);
    expect(Array.from(msg.payload)).toEqual([0x01, 0x02, 0x03]);
  });
});

describe("midi2ChannelVoiceToMidi1Bytes", () => {
  it("down-converts note on/off with scaling", () => {
    const on = midi2ChannelVoiceToMidi1Bytes({ kind: "noteOn", channel: 1, group: 0, note: 60, velocity: 0xffff });
    expect(on).toEqual([0x91, 60, 0x7f]);
    const off = midi2ChannelVoiceToMidi1Bytes({ kind: "noteOff", channel: 1, group: 0, note: 60, velocity: 0x1234 });
    expect(off[0]).toBe(0x81);
    expect(off[1]).toBe(60);
    expect(off[2]).toBeLessThanOrEqual(0x7f);
  });

  it("down-converts program change and bank select when present", () => {
    const bytes = midi2ChannelVoiceToMidi1Bytes({ kind: "programChange", channel: 0, group: 0, program: 5, bankMsb: 1, bankLsb: 2 });
    expect(bytes).toEqual([0xb0, 0x00, 0x01, 0xb0, 0x20, 0x02, 0xc0, 0x05]);
  });

  it("down-converts pitch bend to 14-bit", () => {
    const bytes = midi2ChannelVoiceToMidi1Bytes({ kind: "pitchBend", channel: 2, group: 0, value: 0x80000000 });
    expect(bytes[0]).toBe(0xe2);
    expect(bytes.slice(1)).toEqual([0x00, 0x40]); // center
  });
});

describe("midi2EventsToMidi1Bytes", () => {
  it("applies running status for channel voice", () => {
    const events: Midi2Event[] = [
      { kind: "noteOn", channel: 0, group: 0, note: 60, velocity: 0xffff },
      { kind: "noteOn", channel: 0, group: 0, note: 62, velocity: 0xffff },
    ];
    const bytes = midi2EventsToMidi1Bytes(events);
    expect(bytes).toEqual([0x90, 60, 0x7f, 62, 0x7f]); // status omitted for second due to running status
  });

  it("resets running status on system messages", () => {
    const events: Midi2Event[] = [
      { kind: "noteOn", channel: 0, group: 0, note: 60, velocity: 0xffff },
      { kind: "system", group: 0, status: 0xf8 },
      { kind: "noteOn", channel: 0, group: 0, note: 61, velocity: 0xffff },
    ];
    const bytes = midi2EventsToMidi1Bytes(events);
    expect(bytes).toEqual([0x90, 60, 0x7f, 0xf8, 0x90, 61, 0x7f]);
  });

  it("converts SysEx7 events to MIDI 1.0 bytes", () => {
    const bytes = midi2EventsToMidi1Bytes([
      { kind: "sysex7", group: 0, manufacturerId: [0x7d], payload: Uint8Array.from([0x01, 0x02, 0x03]) },
    ]);
    expect(bytes).toEqual([0xf0, 0x7d, 0x01, 0x02, 0x03, 0xf7]);
  });

  it("converts SysEx8 events to MIDI 1.0 SysEx7 bytes (masked)", () => {
    const bytes = midi2EventsToMidi1Bytes([
      { kind: "sysex8", group: 0, manufacturerId: [0x00, 0x20, 0x33], payload: Uint8Array.from([0x80, 0x7f]) },
    ]);
    expect(bytes).toEqual([0xf0, 0x00, 0x20, 0x33, 0x00, 0x7f, 0xf7]);
  });

  it("converts MIDI-CI events to universal SysEx7 bytes", () => {
    const bytes = midi2EventsToMidi1Bytes([
      {
        kind: "midiCi",
        group: 0,
        scope: "nonRealtime",
        subId2: 0x7c,
        version: 1,
        payload: Uint8Array.from([0x01, 0x02]),
        format: "sysex8",
      },
    ]);
    expect(bytes.slice(0, 5)).toEqual([0xf0, 0x7e, 0x0d, 0x7c, 0x01]);
    expect(bytes[bytes.length - 1]).toBe(0xf7);
  });

  it("ignores unsupported event kinds", () => {
    const bytes = midi2EventsToMidi1Bytes([{ kind: "flexTempo", group: 0, bpm: 120 } as Midi2Event]);
    expect(bytes).toEqual([]);
  });
});
