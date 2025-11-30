import { describe, expect, it } from "vitest";
import { decodeToPacketAndEvent } from "../decoder";
import { encodeNoteOn } from "../ump";

describe("decodeToPacketAndEvent", () => {
  it("returns both packet and event for a note on", () => {
    const words = encodeNoteOn({ kind: "noteOn", group: 0, channel: 0, note: 60, velocity: 0x1234 });
    const decoded = decodeToPacketAndEvent(words);
    expect(decoded?.event?.kind).toBe("noteOn");
    expect(decoded?.packet).toBeTruthy();
  });
});
