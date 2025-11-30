const SYSEX7_MT = 0x3;
const SYSEX8_MT = 0x5;
const SYSEX7_MAX_CHUNK = 6;
const SYSEX8_MAX_CHUNK = 14;
const MAX_PAYLOAD_LENGTH = 0xffff;

export interface SysExMessage {
  manufacturerId: number[];
  payload: Uint8Array;
  group: number;
}

function assertManufacturerId(id: number[]): void {
  if (id.length === 1) {
    if (id[0] === 0x00) throw new RangeError("1-byte manufacturer ID cannot be 0x00.");
  } else if (id.length === 3) {
    if (id[0] !== 0x00) throw new RangeError("3-byte manufacturer ID must start with 0x00.");
  } else {
    throw new RangeError("Manufacturer ID must be length 1 or 3 bytes.");
  }
}

function toUint8Array(data: ArrayLike<number>): Uint8Array {
  return data instanceof Uint8Array ? data : Uint8Array.from(data);
}

function bytesToWords(bytes: Uint8Array): Uint32Array {
  if (bytes.byteLength % 4 !== 0) {
    throw new RangeError("UMP packets must be a multiple of 4 bytes.");
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const words = new Uint32Array(bytes.byteLength / 4);
  for (let i = 0; i < words.length; i++) {
    words[i] = view.getUint32(i * 4, false);
  }
  return words;
}

function wordsToBytes(words: ArrayLike<number>): Uint8Array {
  if (words instanceof Uint8Array) {
    return words;
  }
  const out = new Uint8Array(words.length * 4);
  const view = new DataView(out.buffer);
  Array.from(words).forEach((word, idx) => view.setUint32(idx * 4, Number(word) >>> 0, false));
  return out;
}

function fragmentSysex(kind: "sysex7" | "sysex8", manufacturerId: number[], payload: ArrayLike<number>, group = 0): Uint32Array[] {
  assertManufacturerId(manufacturerId);
  const data = toUint8Array(payload);
  if (data.length > MAX_PAYLOAD_LENGTH) {
    throw new RangeError("SysEx payload too long.");
  }
  if (!Number.isInteger(group) || group < 0 || group > 0x0f) {
    throw new RangeError("Invalid group for SysEx fragmentation.");
  }

  const header = Uint8Array.from(manufacturerId);
  const message = new Uint8Array(header.length + data.length);
  message.set(header, 0);
  message.set(data, header.length);

  const packets: Uint32Array[] = [];
  const maxChunk = kind === "sysex7" ? SYSEX7_MAX_CHUNK : SYSEX8_MAX_CHUNK;
  const mt = kind === "sysex7" ? SYSEX7_MT : SYSEX8_MT;

  let index = 0;
  let packetIndex = 0;
  const totalChunks = Math.ceil(message.length / maxChunk);
  while (index < message.length) {
    const remaining = message.length - index;
    const chunkSize = Math.min(maxChunk, remaining);
    const chunk = message.slice(index, index + chunkSize);
    let status: number;
    if (totalChunks === 1) status = 0x0;
    else if (packetIndex === 0) status = 0x1;
    else if (remaining <= maxChunk) status = 0x3;
    else status = 0x2;

    const payloadBytes = kind === "sysex7" ? 8 : 16;
    const packet = new Uint8Array(payloadBytes);
    packet[0] = (mt << 4) | (group & 0x0f);
    packet[1] = (status << 4) | chunk.length;
    packet.set(chunk, 2);
    // pad remaining bytes with zeros (already zeroed by constructor)
    packets.push(bytesToWords(packet));
    index += chunkSize;
    packetIndex += 1;
  }
  return packets;
}

function reassembleSysex(kind: "sysex7" | "sysex8", packets: ArrayLike<number>[]): SysExMessage {
  if (!packets.length) {
    throw new RangeError("SysEx sequence is empty.");
  }
  if (packets.length > 0xffff) {
    throw new RangeError("SysEx sequence too long.");
  }
  const mt = kind === "sysex7" ? SYSEX7_MT : SYSEX8_MT;
  const maxChunk = kind === "sysex7" ? SYSEX7_MAX_CHUNK : SYSEX8_MAX_CHUNK;
  const bytesPerPacket = kind === "sysex7" ? 8 : 16;

  let group: number | undefined;
  const collected: number[] = [];

  packets.forEach((packetWords, idx) => {
    const bytes = wordsToBytes(packetWords);
    if (bytes.length !== bytesPerPacket) {
      throw new RangeError(`Expected ${bytesPerPacket} bytes per packet.`);
    }
    const mtField = bytes[0] >> 4;
    if (mtField !== mt) {
      throw new RangeError(`Unexpected message type 0x${mtField.toString(16)} in SysEx stream.`);
    }
    const packetGroup = bytes[0] & 0x0f;
    group = group ?? packetGroup;
    if (group !== packetGroup) {
      throw new RangeError("Mixed groups in SysEx sequence.");
    }

    const status = bytes[1] >> 4;
    const count = bytes[1] & 0x0f;
    if (count > maxChunk) {
      throw new RangeError("Invalid chunk length in SysEx packet.");
    }
    if (status === 0x0 && packets.length !== 1) {
      throw new RangeError("Complete SysEx7/8 must be a single packet.");
    }
    const data = Array.from(bytes.slice(2, 2 + maxChunk)).slice(0, count);
    collected.push(...data);

    switch (status) {
      case 0x0:
        if (packets.length !== 1) throw new RangeError("Unexpected packet count for complete SysEx.");
        break;
      case 0x1:
        if (idx !== 0) throw new RangeError("Start packet not first in sequence.");
        break;
      case 0x2:
        if (idx === 0 || idx === packets.length - 1) throw new RangeError("Continue packet in invalid position.");
        break;
      case 0x3:
        if (idx !== packets.length - 1) throw new RangeError("End packet not last in sequence.");
        break;
      default:
        throw new RangeError("Invalid SysEx packet status.");
    }
  });

  if (!collected.length) {
    throw new RangeError("SysEx message payload is empty.");
  }

  const manufacturerId = collected[0] === 0x00 ? collected.slice(0, 3) : [collected[0]];
  assertManufacturerId(manufacturerId);
  const payload = collected.slice(manufacturerId.length);
  return { manufacturerId, payload: Uint8Array.from(payload), group: group ?? 0 };
}

export function fragmentSysEx7(manufacturerId: number[], payload: ArrayLike<number>, group = 0): Uint32Array[] {
  return fragmentSysex("sysex7", manufacturerId, payload, group);
}

export function reassembleSysEx7(packets: ArrayLike<number>[]): SysExMessage {
  return reassembleSysex("sysex7", packets);
}

export function fragmentSysEx8(manufacturerId: number[], payload: ArrayLike<number>, group = 0): Uint32Array[] {
  return fragmentSysex("sysex8", manufacturerId, payload, group);
}

export function reassembleSysEx8(packets: ArrayLike<number>[]): SysExMessage {
  return reassembleSysex("sysex8", packets);
}

export function wordsToUMPBytes(words: ArrayLike<number>): Uint8Array {
  return wordsToBytes(words);
}

export function umpBytesToWords(bytes: Uint8Array): Uint32Array {
  return bytesToWords(bytes);
}
