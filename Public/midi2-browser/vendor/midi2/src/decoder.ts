import { UmpPacket } from "./generated/openapi-types";
import { decodeUmp } from "./ump";
import { Midi2Event } from "./types";
import { eventToSchemaPacket, decodeStreamWord } from "./schema-bridge";

export interface DecodedUmp {
  packet: UmpPacket | null;
  event: Midi2Event | null;
}

/**
 * Decode UMP words into both the OpenAPI `UmpPacket` (when mappable) and a high-level `Midi2Event`.
 * Stream MT=0xF packets are translated into `StreamEvent` when possible.
 */
export function decodeToPacketAndEvent(words: ArrayLike<number>): DecodedUmp | null {
  let event = decodeUmp(words);
  if (!event) return null;
  const word0 = words[0] ?? 0;
  const mt = (word0 >>> 28) & 0xf;
  if (event.kind === "rawUMP" && mt === 0xf) {
    const stream = decodeStreamWord(word0);
    if (stream) {
      event = stream;
    }
  }
  const packet = eventToSchemaPacket(event);
  return { packet, event };
}
