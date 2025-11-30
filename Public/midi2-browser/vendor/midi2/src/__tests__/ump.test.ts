import { describe, expect, it } from "vitest";
import {
  decodeUmp,
  encodeControlChange,
  encodeEventPackets,
  encodeNoteOn,
  encodeNrpn,
  encodeNrpnRelative,
  encodePerNoteAssignableController,
  encodePerNoteManagement,
  encodePerNoteRegisteredController,
  encodePitchBend,
  encodeProgramChange,
  encodeRpn,
  encodeRpnRelative,
  encodeUmp,
} from "../ump";
import { fragmentSysEx7, fragmentSysEx8, reassembleSysEx7, reassembleSysEx8, umpBytesToWords, wordsToUMPBytes } from "../sysex";
import { decodeMidiCiFromSysEx, encodeMidiCiEvent } from "../midici";
import {
  Midi2ControlChangeEvent,
  Midi2NoteOnEvent,
  Midi2NrpnEvent,
  Midi2NrpnRelativeEvent,
  Midi2PerNoteAssignableControllerEvent,
  Midi2PerNoteManagementEvent,
  Midi2PerNoteRegisteredControllerEvent,
  Midi2PitchBendEvent,
  Midi2ProgramChangeEvent,
  Midi2RpnEvent,
  Midi2RpnRelativeEvent,
  StreamEvent,
  MidiCiEvent,
  SysEx7Event,
  SysEx8Event,
  Midi2SystemEvent,
  Midi1ChannelVoiceEvent,
  UtilityEvent,
  FlexTempoEvent,
  FlexTimeSignatureEvent,
  FlexKeySignatureEvent,
  FlexLyricEvent,
} from "../types";

describe("UMP channel voice encode/decode", () => {
  it("encodes and decodes note on", () => {
    const evt: Midi2NoteOnEvent = {
      kind: "noteOn",
      group: 0,
      channel: 0,
      note: 60,
      velocity: 0x1234,
      attributeType: 0,
    };
    const words = encodeNoteOn(evt);
    expect(words[0]).toBe(0x40903c00);
    expect(words[1]).toBe(0x12340000);
    const decoded = decodeUmp(words, 10);
    expect(decoded).toMatchObject({
      kind: "noteOn",
      group: 0,
      channel: 0,
      note: 60,
      velocity: 0x1234,
      attributeType: 0,
      attributeData: 0,
      timestamp: 10,
    });
  });

  it("encodes and decodes control change", () => {
    const evt: Midi2ControlChangeEvent = {
      kind: "controlChange",
      group: 1,
      channel: 2,
      controller: 7,
      value: 0x12345678,
    };
    const words = encodeControlChange(evt);
    expect(words[0]).toBe(0x41b20700);
    expect(words[1]).toBe(0x12345678);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject({
      kind: "controlChange",
      controller: 7,
      value: 0x12345678,
      group: 1,
      channel: 2,
    });
  });

  it("encodes and decodes pitch bend", () => {
    const evt: Midi2PitchBendEvent = {
      kind: "pitchBend",
      group: 0,
      channel: 3,
      value: 0x90000000,
    };
    const words = encodePitchBend(evt);
    expect(words[0]).toBe(0x40e30000);
    expect(words[1]).toBe(0x90000000);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject({
      kind: "pitchBend",
      group: 0,
      channel: 3,
      value: 0x90000000,
    });
  });

  it("encodes and decodes program change with bank select", () => {
    const evt: Midi2ProgramChangeEvent = {
      kind: "programChange",
      group: 0,
      channel: 1,
      program: 5,
      bankMsb: 1,
      bankLsb: 2,
    };
    const words = encodeProgramChange(evt);
    expect(words[0]).toBe(0x40c10580);
    expect(words[1]).toBe(0x01020000);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject({
      kind: "programChange",
      program: 5,
      bankMsb: 1,
      bankLsb: 2,
      channel: 1,
    });
  });

  it("encodes and decodes RPN absolute", () => {
    const evt: Midi2RpnEvent = {
      kind: "rpn",
      group: 0,
      channel: 0,
      bank: 0x12,
      index: 0x34,
      value: 0x01020304,
    };
    const words = encodeRpn(evt);
    expect(words[0]).toBe(0x40201234);
    expect(words[1]).toBe(0x01020304);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject(evt);
  });

  it("encodes and decodes NRPN relative", () => {
    const evt: Midi2NrpnRelativeEvent = {
      kind: "nrpnRelative",
      group: 1,
      channel: 2,
      bank: 0x01,
      index: 0x02,
      delta: -1234,
    };
    const words = encodeNrpnRelative(evt);
    expect(words[0]).toBe(0x41520102);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject({
      kind: "nrpnRelative",
      group: 1,
      channel: 2,
      bank: 1,
      index: 2,
      delta: -1234,
    });
  });

  it("encodes and decodes per-note management and per-note controllers", () => {
    const mgmt: Midi2PerNoteManagementEvent = {
      kind: "perNoteManagement",
      group: 0,
      channel: 0,
      note: 60,
      detach: true,
      reset: false,
    };
    const mgmtWords = encodePerNoteManagement(mgmt);
    expect(mgmtWords[0]).toBe(0x40f03c02);
    const mgmtDecoded = decodeUmp(mgmtWords);
    expect(mgmtDecoded).toMatchObject(mgmt);

    const reg: Midi2PerNoteRegisteredControllerEvent = {
      kind: "perNoteRegisteredController",
      group: 0,
      channel: 0,
      note: 60,
      controller: 10,
      value: 0x0abcddcc,
    };
    const regWords = encodePerNoteRegisteredController(reg);
    expect(regWords[0]).toBe(0x40f03c0a);
    const regDecoded = decodeUmp(regWords);
    expect(regDecoded).toMatchObject(reg);

    const assign: Midi2PerNoteAssignableControllerEvent = {
      kind: "perNoteAssignableController",
      group: 0,
      channel: 0,
      note: 60,
      controller: 0x85,
      value: 0x01020304,
    };
    const assignWords = encodePerNoteAssignableController(assign);
    expect(assignWords[0]).toBe(0x40f03c85);
    const assignDecoded = decodeUmp(assignWords);
    expect(assignDecoded).toMatchObject(assign);
  });

  it("encodes and decodes per-note pitch bend", () => {
    const evt = { kind: "perNotePitchBend", group: 0, channel: 2, note: 60, value: 0x80000000 };
    const words = encodeUmp(evt as any);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject(evt);
  });

  it("passes through unknown message types as raw UMP", () => {
    const words = new Uint32Array([0xe0000000, 0x01020304]);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject({
      kind: "rawUMP",
      words,
    });
  });

  it("encodes and decodes system common/realtime", () => {
    const clock: Midi2SystemEvent = { kind: "system", group: 0, status: 0xf8 };
    const clockWords = encodeUmp(clock);
    expect(clockWords[0]).toBe(0x10f80000);
    const clockDecoded = decodeUmp(clockWords);
    expect(clockDecoded).toMatchObject(clock);

    const spp: Midi2SystemEvent = { kind: "system", group: 1, status: 0xf2, data1: 0x01, data2: 0x02 };
    const sppWords = encodeUmp(spp);
    expect(sppWords[0]).toBe(0x11f20102);
    const sppDecoded = decodeUmp(sppWords);
    expect(sppDecoded).toMatchObject(spp);
  });

  it("encodes and decodes MIDI 1.0 channel voice (mt=0x2)", () => {
    const evt: Midi1ChannelVoiceEvent = {
      kind: "midi1ChannelVoice",
      group: 0,
      status: 0x90,
      data1: 60,
      data2: 100,
    };
    const words = encodeUmp(evt);
    expect(words[0]).toBe(0x20903c64);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject(evt);
  });

  it("encodes and decodes utility messages (mt=0x0)", () => {
    const noop: UtilityEvent = { kind: "utility", status: "noop" };
    expect(encodeUmp(noop)[0]).toBe(0x00000000);
    const jrClock: UtilityEvent = { kind: "utility", status: "jrClock", value: 0x1234 };
    const clockWords = encodeUmp(jrClock);
    expect(clockWords[0]).toBe(0x00011234);
    const decoded = decodeUmp(clockWords);
    expect(decoded).toMatchObject(jrClock);
  });

  it("encodes and decodes flex tempo", () => {
    const evt: FlexTempoEvent = { kind: "flexTempo", group: 0, bpm: 120 };
    const words = encodeUmp(evt);
    expect(words[0]).toBe(0xd0100100);
    const decoded = decodeUmp(words);
    expect(decoded?.kind).toBe("flexTempo");
    expect((decoded as FlexTempoEvent).bpm).toBeCloseTo(120, 3);
  });

  it("encodes and decodes flex time signature", () => {
    const evt: FlexTimeSignatureEvent = { kind: "flexTimeSignature", group: 1, channel: 2, numerator: 3, denominatorPow2: 2 };
    const words = encodeUmp(evt);
    expect(words[0]).toBe(0xd1100212);
    expect(words[1]).toBe(0x03020000);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject(evt);
  });

  it("encodes and decodes flex key signature", () => {
    const evt: FlexKeySignatureEvent = { kind: "flexKeySignature", group: 2, key: "C#m" };
    const words = encodeUmp(evt);
    expect(words[0]).toBe(0xd2100400);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject(evt);
  });

  it("encodes and decodes flex lyric", () => {
    const evt: FlexLyricEvent = { kind: "flexLyric", group: 0, channel: 1, text: "hello" };
    const words = encodeUmp(evt);
    expect(words[0]).toBe(0xd0110211);
    const decoded = decodeUmp(words);
    expect(decoded).toMatchObject(evt);
  });
});

describe("Stream messages", () => {
  it("encodes and decodes stream config request/notification", () => {
    const req: StreamEvent = {
      kind: "stream",
      group: 1,
      opcode: "streamConfigRequest",
      streamConfigRequest: { protocol: "midi2", jrTimestampsTx: true, jrTimestampsRx: true },
    };
    const reqWords = encodeUmp(req);
    const decodedReq = decodeUmp(reqWords);
    expect(decodedReq).toMatchObject({
      kind: "stream",
      opcode: "streamConfigRequest",
      streamConfigRequest: { protocol: "midi2", jrTimestampsTx: true, jrTimestampsRx: true },
    });

    const notif: StreamEvent = {
      kind: "stream",
      group: 1,
      opcode: "streamConfigNotification",
      streamConfigNotification: { protocol: "midi1", jrTimestampsTx: false, jrTimestampsRx: false },
    };
    const notifWords = encodeUmp(notif);
    const decodedNotif = decodeUmp(notifWords);
    expect(decodedNotif).toMatchObject({ kind: "stream", opcode: "streamConfigNotification" });
  });

  it("encodes and decodes function block info and discovery", () => {
    const info: StreamEvent = {
      kind: "stream",
      group: 0,
      opcode: "functionBlockInfo",
      functionBlockInfo: { index: 2, firstGroup: 1, groupCount: 4 },
    };
    const infoWords = encodeUmp(info);
    expect(infoWords[0]).toBe(0xf0020214);
    const decodedInfo = decodeUmp(infoWords);
    expect(decodedInfo).toMatchObject({
      kind: "stream",
      opcode: "functionBlockInfo",
      functionBlockInfo: { index: 2, firstGroup: 1, groupCount: 4 },
    });

    const discovery: StreamEvent = {
      kind: "stream",
      group: 0,
      opcode: "functionBlockDiscovery",
      functionBlockDiscovery: { filterBitmap: 0x8001 },
    };
    const discWords = encodeUmp(discovery);
    const decodedDisc = decodeUmp(discWords);
    expect(decodedDisc).toMatchObject({ kind: "stream", opcode: "functionBlockDiscovery" });
  });

  it("rejects stream packets with reserved bits", () => {
    const word = new Uint32Array([0xf0000800]);
    expect(() => decodeUmp(word)).toThrow(RangeError);
    const endpointWord = new Uint32Array([0xf0000101]);
    expect(() => decodeUmp(endpointWord)).toThrow(RangeError);
  });
});

describe("SysEx helpers", () => {
  it("fragments and reassembles SysEx7", () => {
    const packets = fragmentSysEx7([0x7d], [1, 2, 3, 4, 5, 6, 7], 2);
    expect(packets.length).toBe(2);
    const result = reassembleSysEx7(packets);
    expect(result.group).toBe(2);
    expect(result.manufacturerId).toEqual([0x7d]);
    expect(Array.from(result.payload)).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });

  it("fragments and reassembles SysEx8", () => {
    const payload = Array.from({ length: 18 }, (_, i) => i + 1);
    const packets = fragmentSysEx8([0x00, 0x20, 0x33], payload, 3);
    expect(packets.length).toBe(2);
    const result = reassembleSysEx8(packets);
    expect(result.group).toBe(3);
    expect(result.manufacturerId).toEqual([0x00, 0x20, 0x33]);
    expect(Array.from(result.payload)).toEqual(payload);
  });

  it("rejects mixed-group SysEx sequences", () => {
    const packets = fragmentSysEx7([0x7d], [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0);
    const tampered = packets.map((p, idx) => {
      if (idx === 0) return p;
      const bytes = wordsToUMPBytes(p);
      bytes[0] = (bytes[0] & 0xf0) | 0x01; // force different group nibble
      return umpBytesToWords(bytes);
    });
    expect(() => reassembleSysEx7(tampered)).toThrow(RangeError);
  });

  it("encodes SysEx7 events via encodeEventPackets", () => {
    const evt: SysEx7Event = {
      kind: "sysex7",
      group: 1,
      manufacturerId: [0x7d],
      payload: Uint8Array.from([1, 2, 3, 4]),
    };
    const packets = encodeEventPackets(evt);
    expect(packets.length).toBe(1);
    const decoded = reassembleSysEx7(packets);
    expect(decoded.manufacturerId).toEqual([0x7d]);
    expect(Array.from(decoded.payload)).toEqual([1, 2, 3, 4]);
    expect(decoded.group).toBe(1);
  });

  it("rejects SysEx with invalid group number", () => {
    expect(() => fragmentSysEx7([0x7d], [1, 2], 0x10)).toThrow(RangeError);
  });

  it("rejects SysEx with too many packets", () => {
    const packets = Array.from({ length: 0x10000 }, () => fragmentSysEx7([0x7d], [1], 0)[0]);
    expect(() => reassembleSysEx7(packets)).toThrow(RangeError);
  });

  it("encodes and decodes MIDI-CI envelope", () => {
    const env: MidiCiEvent = {
      kind: "midiCi",
      group: 2,
      scope: "nonRealtime",
      subId2: 0x7c,
      version: 1,
      payload: Uint8Array.from([0x01, 0x02, 0x03]),
      format: "sysex8",
    };
    const packets = encodeMidiCiEvent(env);
    const asSysEx: SysEx8Event = {
      kind: "sysex8",
      group: 2,
      manufacturerId: [0x7e],
      payload: Uint8Array.from([0x7e, 0x0d, 0x7c, 0x01, 0x01, 0x02, 0x03]),
    };
    const decoded = decodeMidiCiFromSysEx(asSysEx);
    expect(decoded).toMatchObject({
      group: 2,
      scope: "nonRealtime",
      subId2: 0x7c,
      version: 1,
      payload: Uint8Array.from([0x01, 0x02, 0x03]),
      format: "sysex8",
    });
  });
});
