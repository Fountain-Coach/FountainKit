import { describe, expect, it } from "vitest";
import { isUmpPacket } from "../generated/openapi-types";
import { decodeWordsToSchemaPacket, eventToSchemaPacket, eventToSchemaPacketWords, schemaPacketToEvent, schemaPacketToWords } from "../schema-bridge";
import { decodeUmp, encodeUmp } from "../ump";
import {
  MidiCiEvent,
  FlexTempoEvent,
  Midi1ChannelVoiceEvent,
  Midi2NoteOnEvent,
  Midi2ProgramChangeEvent,
  StreamEvent,
  SysEx7Event,
  SysEx8Event,
  ProfileEvent,
  PropertyExchangeEvent,
} from "../types";

describe("schema bridge", () => {
  it("converts midi2 note on events to schema packets and back", () => {
    const evt: Midi2NoteOnEvent = { kind: "noteOn", group: 0, channel: 1, note: 64, velocity: 0x1234 };
    const packet = eventToSchemaPacket(evt);
    expect(packet && isUmpPacket(packet)).toBe(true);
    const words = schemaPacketToWords(packet!);
    expect(words).toEqual([encodeUmp(evt)]);
    const backToEvent = schemaPacketToEvent(packet!);
    expect(backToEvent).toMatchObject(evt);
    const fromWords = decodeWordsToSchemaPacket(words![0]);
    expect(fromWords && isUmpPacket(fromWords)).toBe(true);
  });

  it("supports program change with bank select flags", () => {
    const evt: Midi2ProgramChangeEvent = {
      kind: "programChange",
      group: 0,
      channel: 2,
      program: 10,
      bankMsb: 1,
      bankLsb: 2,
    };
    const words = eventToSchemaPacketWords(evt);
    expect(words).toEqual([encodeUmp(evt)]);
    const decoded = decodeUmp(words![0]);
    expect(decoded).toMatchObject(evt);
  });

  it("supports midi1 channel voice packets via schema", () => {
    const evt: Midi1ChannelVoiceEvent = {
      kind: "midi1ChannelVoice",
      group: 1,
      status: 0x90,
      data1: 60,
      data2: 100,
    };
    const packet = eventToSchemaPacket(evt);
    expect(packet && isUmpPacket(packet)).toBe(true);
    const words = schemaPacketToWords(packet!);
    expect(words).toEqual([encodeUmp(evt)]);
    const roundtripEvent = schemaPacketToEvent(packet!);
    expect(roundtripEvent).toMatchObject(evt);
  });

  it("maps flex tempo to schema envelope", () => {
    const evt: FlexTempoEvent = { kind: "flexTempo", group: 0, bpm: 128.5 };
    const packet = eventToSchemaPacket(evt);
    expect(packet && isUmpPacket(packet)).toBe(true);
    const words = schemaPacketToWords(packet!);
    const decoded = decodeUmp(words![0]);
    expect(decoded).toMatchObject(evt);
  });

  it("roundtrips SysEx7 via schema packets", () => {
    const evt: SysEx7Event = {
      kind: "sysex7",
      group: 2,
      manufacturerId: [0x7d],
      payload: Uint8Array.from([1, 2, 3, 4, 5, 6, 7, 8]),
    };
    const packet = eventToSchemaPacket(evt);
    expect(packet && isUmpPacket(packet)).toBe(true);
    const words = schemaPacketToWords(packet!);
    expect(words && words.length).toBeGreaterThan(1);
    const backToEvent = schemaPacketToEvent(packet!);
    expect(backToEvent).toMatchObject({ kind: "sysex7", manufacturerId: [0x7d] });
  });

  it("roundtrips SysEx8 via schema packets", () => {
    const evt: SysEx8Event = {
      kind: "sysex8",
      group: 1,
      manufacturerId: [0x00, 0x20, 0x33],
      payload: Uint8Array.from([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    };
    const packet = eventToSchemaPacket(evt);
    expect(packet && isUmpPacket(packet)).toBe(true);
    const words = schemaPacketToWords(packet!);
    expect(words && words.length).toBe(1);
    const decoded = schemaPacketToEvent(packet!);
    expect(decoded).toMatchObject({ kind: "sysex8", manufacturerId: [0x00, 0x20, 0x33] });
  });

  it("supports MIDI-CI envelope mapping (sysex8)", () => {
    const env: MidiCiEvent = {
      kind: "midiCi",
      group: 0,
      scope: "nonRealtime",
      subId2: 0x7c,
      version: 1,
      payload: Uint8Array.from([0x01, 0x02, 0x03]),
      format: "sysex8",
    };
    const packet = eventToSchemaPacket(env);
    expect(packet && isUmpPacket(packet)).toBe(true);
    const evt = schemaPacketToEvent(packet!);
    expect(evt?.kind).toBe("midiCi");
  });

  it("encodes/decodes profile command via MIDI-CI", () => {
    const profile: ProfileEvent = {
      kind: "profile",
      group: 0,
      command: "inquiry",
      profileId: "com.fountain.test.profile",
      target: "group",
      channels: [1, 2],
      details: { version: 1 },
    };
    const packet = eventToSchemaPacket(profile);
    expect(packet).toBeTruthy();
    const evt = schemaPacketToEvent(packet!);
    expect(evt?.kind).toBe("profile");
  });

  it("encodes/decodes property exchange notify via MIDI-CI", () => {
    const pe: PropertyExchangeEvent = {
      kind: "propertyExchange",
      group: 1,
      command: "notify",
      requestId: 42,
      header: { schema: "test" },
      data: { hello: "world" },
      ack: { ack: true, statusCode: 0, message: "ok" },
    };
    const packet = eventToSchemaPacket(pe);
    expect(packet).toBeTruthy();
    const evt = schemaPacketToEvent(packet!);
    expect(evt?.kind === "propertyExchange" || evt?.kind === "midiCi").toBe(true);
  });

  it("encodes/decodes profile enable/disable commands", () => {
    const enable: ProfileEvent = {
      kind: "profile",
      group: 0,
      command: "setOn",
      profileId: "com.fountain.test.profile",
      target: "channel",
      channels: [0],
    };
    const disable: ProfileEvent = { ...enable, command: "setOff" };
    const enablePacket = eventToSchemaPacket(enable);
    const disablePacket = eventToSchemaPacket(disable);
    expect(schemaPacketToEvent(enablePacket!)?.kind).toBe("profile");
    expect(schemaPacketToEvent(disablePacket!)?.kind).toBe("profile");
  });

  it("encodes/decodes property exchange setReply with ack", () => {
    const pe: PropertyExchangeEvent = {
      kind: "propertyExchange",
      group: 2,
      command: "setReply",
      requestId: 7,
      header: { schema: "foo", contentType: "application/json" },
      data: { status: "ok" },
      ack: { ack: true, statusCode: 0, message: "ok" },
    };
    const packet = eventToSchemaPacket(pe);
    const evt = schemaPacketToEvent(packet!);
    expect(evt?.kind).toBe("propertyExchange");
  });

  it("falls back to notify when PE command is invalid", () => {
    const badPayload = new TextEncoder().encode(JSON.stringify({ command: "bogus", data: "0x0102" }));
    const env: MidiCiEvent = { kind: "midiCi", group: 0, scope: "nonRealtime", subId2: 0x21, version: 1, payload: badPayload, format: "sysex7" };
    const evt = schemaPacketToEvent(eventToSchemaPacket(env)!);
    expect(evt?.kind).toBe("propertyExchange");
    expect((evt as any).command).toBe("notify");
  });

  it("downgrades PE with missing requestId", () => {
    const env: MidiCiEvent = {
      kind: "midiCi",
      group: 0,
      scope: "nonRealtime",
      subId2: 0x21,
      version: 1,
      payload: new TextEncoder().encode(JSON.stringify({ command: "set", encoding: "json", data: {} })),
      format: "sysex7",
    };
    const evt = schemaPacketToEvent(eventToSchemaPacket(env)!);
    expect(evt?.kind).toBe("propertyExchange");
    expect((evt as any).command).toBe("notify");
  });

  it("downgrades PE with invalid encoding", () => {
    const payload = new TextEncoder().encode(JSON.stringify({ command: "set", requestId: 1, encoding: "bogus", data: {} }));
    const env: MidiCiEvent = { kind: "midiCi", group: 0, scope: "nonRealtime", subId2: 0x21, version: 1, payload, format: "sysex7" };
    const evt = schemaPacketToEvent(eventToSchemaPacket(env)!);
    expect(evt?.kind).toBe("propertyExchange");
    expect((evt as any).command).toBe("notify");
  });

  it("downgrades profile with missing profileId", () => {
    const payload = new TextEncoder().encode(JSON.stringify({ command: "setOn", target: "channel", channels: [0] }));
    const env: MidiCiEvent = { kind: "midiCi", group: 0, scope: "nonRealtime", subId2: 0x20, version: 1, payload, format: "sysex7" };
    const evt = schemaPacketToEvent(eventToSchemaPacket(env)!);
    expect(evt?.kind).toBe("profile");
    expect((evt as any).command).toBe("reply");
  });

  it("falls back to endReport when process inquiry command is invalid", () => {
    const badPi = new TextEncoder().encode(JSON.stringify({ command: "bogus" }));
    const env: MidiCiEvent = { kind: "midiCi", group: 0, scope: "nonRealtime", subId2: 0x22, version: 1, payload: badPi, format: "sysex7" };
    const evt = schemaPacketToEvent(eventToSchemaPacket(env)!);
    expect(evt?.kind).toBe("processInquiry");
    expect((evt as any).command).toBe("endReport");
  });

  it("treats stream/profile/property-exchange packets as raw when unsupported", () => {
    const streamEvt: StreamEvent = {
      kind: "stream",
      group: 0,
      opcode: "endpointDiscovery",
      endpointDiscovery: { majorVersion: 1, minorVersion: 0, maxGroups: 1 },
    };
    const packet = eventToSchemaPacket(streamEvt);
    expect(packet).toBeTruthy();
    const evt = schemaPacketToEvent(packet!);
    expect(evt).toMatchObject({ kind: "stream", opcode: "endpointDiscovery" });
  });
});
