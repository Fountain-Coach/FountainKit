import { describe, expect, it } from "vitest";
import {
  Flex_Tempo,
  Midi2_NoteOn,
  UmpPacket64,
  isFlex_Tempo,
  isMidi2_NoteOn,
  isUmpPacket64,
} from "../generated/openapi-types";

describe("OpenAPI generated types and guards", () => {
  it("validates Midi2_NoteOn ranges", () => {
    const ok: Midi2_NoteOn = {
      noteNumber: 60,
      velocity16: 0x1234,
      attributeType: 0,
      attributeData16: 0,
    };
    expect(isMidi2_NoteOn(ok)).toBe(true);

    const bad = { noteNumber: 0x80, velocity16: 0 } as unknown;
    expect(isMidi2_NoteOn(bad)).toBe(false);
  });

  it("validates UMP packet framing for note-on", () => {
    const packet: UmpPacket64 = {
      messageType: 4,
      group: 1,
      statusNibble: 9,
      channel: 2,
      body: {
        statusNibble: 9,
        channel: 2,
        body: {
          noteNumber: 64,
          velocity16: 0x4000,
        },
      },
    };
    expect(isUmpPacket64(packet)).toBe(true);

    const broken = { ...packet, group: 20 } as unknown;
    expect(isUmpPacket64(broken)).toBe(false);
  });

  it("validates flex tempo envelope", () => {
    const tempo: Flex_Tempo = { statusClass: 16, status: 1, data: { bpm: 120 } };
    expect(isFlex_Tempo(tempo)).toBe(true);
    expect(isFlex_Tempo({ statusClass: 16, status: 1, data: { bpm: 0 } })).toBe(false);
  });
});
