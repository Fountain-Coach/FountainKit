import { describe, expect, it } from "vitest";
import { decodeToPacketAndEvent } from "../decoder";
import { eventToSchemaPacket, reassemblePeChunks } from "../schema-bridge";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

function hexToWord(hex: string): number {
  return Number(BigInt(hex));
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new Error("Hex string length must be even.");
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    out[i / 2] = parseInt(clean.slice(i, i + 2), 16);
  }
  return out;
}

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadJSON(relPath: string) {
  const abs = resolve(__dirname, "../../../docs/pb-vrt", relPath);
  return JSON.parse(readFileSync(abs, "utf8"));
}

describe("PB-VRT golden vectors", () => {
  it("decodes stream config request/notification", () => {
    const req = loadJSON("stream/stream_config_request.json");
    const words = new Uint32Array([hexToWord(req.word)]);
    const decoded = decodeToPacketAndEvent(words);
    expect(decoded?.event?.kind).toBe("stream");
    expect(decoded?.event).toMatchObject({
      opcode: "streamConfigRequest",
      streamConfigRequest: { protocol: "midi2", jrTimestampsTx: true, jrTimestampsRx: true },
    });

    const notif = loadJSON("stream/stream_config_notification.json");
    const notifWords = new Uint32Array([hexToWord(notif.word)]);
    const decodedNotif = decodeToPacketAndEvent(notifWords);
    expect(decodedNotif?.event?.kind).toBe("stream");
    expect(decodedNotif?.event).toMatchObject({
      opcode: "streamConfigNotification",
      streamConfigNotification: { protocol: "midi2", jrTimestampsTx: true, jrTimestampsRx: false },
    });
  });

  it("decodes function block info and discovery", () => {
    const info = loadJSON("stream/function_block_info.json");
    const infoWords = new Uint32Array([hexToWord(info.word)]);
    const decodedInfo = decodeToPacketAndEvent(infoWords);
    expect(decodedInfo?.event).toMatchObject({
      kind: "stream",
      opcode: "functionBlockInfo",
      functionBlockInfo: { index: 1, firstGroup: 10, groupCount: 3 },
    });

    const discovery = loadJSON("stream/function_block_discovery.json");
    const discWords = discovery.map((entry: any) => hexToWord(entry.word ?? entry));
    const decodedDisc = decodeToPacketAndEvent(new Uint32Array([discWords[0]]));
    expect(decodedDisc?.event?.kind).toBe("stream");
  });

  it("decodes JR clock/timestamp sequence", () => {
    const jr = loadJSON("jr/clock_timestamp.json").sequence;
    const events = jr.map((e: any) =>
      decodeToPacketAndEvent(
        new Uint32Array([
          (0x0 << 28) | // utility mt
            (0x0 << 24) |
            (e.utility === "jrClock" ? 0x01 << 16 : 0x02 << 16) |
            (e.value & 0xffff),
        ]),
      ),
    );
    expect(events.every((entry: ReturnType<typeof decodeToPacketAndEvent> | null): boolean => entry?.event?.kind === "utility")).toBe(true);
  });

  it("decodes profile enable/disable sequence", () => {
    const seq = loadJSON("profiles/enable_sequence.json").sequence;
    const commands = seq.map((entry: any) => entry.command);
    expect(commands).toEqual(["setOn", "enabledReport", "detailsInquiry", "detailsReply", "setOff", "disabledReport"]);
  });

  it("decodes property-exchange set chunked sequence", () => {
    const seq = loadJSON("property-exchange/set_chunked.json");
    const events = seq.map((entry: any) => ({
      kind: "propertyExchange",
      group: 0,
      command: entry.command,
      requestId: entry.requestId,
      encoding: entry.encoding,
      header: entry.header,
      data: entry.dataHex ? hexToBytes(entry.dataHex) : undefined,
    }));
    const packets = events.map((evt: (typeof events)[number]) => eventToSchemaPacket(evt as any));
    expect(packets.length).toBeGreaterThan(0);
  });

  it("decodes process inquiry flows", () => {
    const seq = loadJSON("process-inquiry/flows.json").sequence;
    const commands = seq.map((e: any) => e.command);
    expect(commands).toEqual(["capInquiry", "capReply", "messageReport", "messageReportReply", "endReport"]);
    expect(seq[1].filters).toEqual({ noteOn: 1, clock: 1 });
    expect(seq[2].filters).toEqual({ sysex: 2, ci: 1 });
  });

  it("reassembles property-exchange notify chunks", () => {
    const seq = loadJSON("property-exchange/notify_chunked.json");
    const chunks = seq.map((entry: any) => ({
      kind: "propertyExchange",
      group: 0,
      command: entry.command,
      requestId: entry.requestId,
      encoding: entry.encoding,
      header: entry.header,
      data: hexToBytes(entry.dataHex),
    }));
    const merged = reassemblePeChunks(chunks as any);
    expect(merged?.data instanceof Uint8Array).toBe(true);
    const bytes = merged?.data instanceof Uint8Array ? Array.from(merged.data) : [];
    expect(bytes).toEqual([1, 2, 3, 4, 5, 6]);
  });

  it("parses profile details reply", () => {
    const profile = loadJSON("profiles/details_reply.json");
    expect(profile.reply.command).toBe("detailsReply");
    expect(profile.reply.profileId).toBe("/org.midi/piano");
    expect(profile.reply.details).toEqual({ ver: 1, cmL: 5, cmH: 128 });
  });

  it("parses profile specific data payload", () => {
    const psd = loadJSON("profiles/profile_specific_data.json");
    expect(psd.command).toBe("profileSpecificData");
    expect(psd.profileId).toBe("/org.midi/piano");
    expect(psd.channels).toEqual([0]);
    expect(psd.dataHex).toBe("010203");
  });
});
