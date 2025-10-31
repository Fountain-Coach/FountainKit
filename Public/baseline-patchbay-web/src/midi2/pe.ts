// Build MIDI-CI Property Exchange (PE) SysEx7 payload bytes compatible with MetalInstrument

// 7-bit encode helpers mirror External/_gh/midi2 MidiCiPropertyExchangeBody.sysEx7Bytes
function encodeUInt32To7Bit(n: number): number[] {
  const v = Math.max(0, Math.floor(n)) >>> 0
  return [ (v >>> 21) & 0x7F, (v >>> 14) & 0x7F, (v >>> 7) & 0x7F, v & 0x7F ]
}

export type PECommand = 'capInquiry' | 'capReply' | 'get' | 'getReply' | 'set' | 'setReply' | 'subscribe' | 'subscribeReply' | 'notify' | 'terminate'

const CommandMap: Record<PECommand, number> = {
  capInquiry: 0, capReply: 1, get: 2, getReply: 3, set: 4, setReply: 5, subscribe: 6, subscribeReply: 7, notify: 8, terminate: 9
}

// Returns SysEx7 payload for a PE envelope: [scope(0x7E), 0x0D, subId2(0x7C), version(1), body...]
export function buildPESysEx7Body(command: PECommand, requestId: number, header: Record<string, string>, data: Uint8Array): Uint8Array {
  const cmdByte = CommandMap[command] & 0x7F
  const req = encodeUInt32To7Bit(requestId)
  const enc = 0 // json
  const headerBytes = header && Object.keys(header).length > 0 ? new TextEncoder().encode(JSON.stringify(header)) : new Uint8Array(0)
  const headerLen = Math.min(127, headerBytes.length) & 0x7F
  const header7 = new Uint8Array(headerLen)
  for (let i = 0; i < headerLen; i++) header7[i] = headerBytes[i] & 0x7F
  const dataLen = Math.min(127, data.length) & 0x7F
  const data7 = new Uint8Array(dataLen)
  for (let i = 0; i < dataLen; i++) data7[i] = data[i] & 0x7F
  const body = new Uint8Array(1 + 4 + 1 + 1 + header7.length + 1 + data7.length)
  let o = 0
  body[o++] = cmdByte
  for (const b of req) body[o++] = b
  body[o++] = enc
  body[o++] = headerLen
  body.set(header7, o); o += header7.length
  body[o++] = dataLen
  body.set(data7, o)
  return body
}

export function wrapCiEnvelopeSysEx7(body: Uint8Array, { realtime = false, version = 1 }: { realtime?: boolean; version?: number } = {}): Uint8Array {
  const scope = realtime ? 0x7F : 0x7E
  const out = new Uint8Array(4 + body.length)
  out[0] = scope
  out[1] = 0x0D
  out[2] = 0x7C // PE
  out[3] = version & 0x7F
  out.set(body, 4)
  return out
}

export function buildPESetSysEx7(properties: Record<string, number>, requestId = 1): Uint8Array {
  const props = Object.entries(properties).map(([name, value]) => ({ name, value }))
  const json = new TextEncoder().encode(JSON.stringify({ properties: props }))
  const peBody = buildPESysEx7Body('set', requestId, {}, json)
  return wrapCiEnvelopeSysEx7(peBody)
}

