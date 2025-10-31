// Minimal UMP helpers for SysEx7 and vendor JSON encoding

export type UmpWords = number[]

// Split SysEx7 bytes into UMP 64-bit packets (2 words per packet)
export function encodeSysEx7UMP(bytes: Uint8Array, group = 0): UmpWords {
  const chunks: Uint8Array[] = []
  for (let i = 0; i < bytes.length; i += 6) {
    chunks.push(bytes.slice(i, Math.min(i + 6, bytes.length)))
  }
  const words: number[] = []
  chunks.forEach((chunk, idx) => {
    const isSingle = chunks.length === 1
    const isFirst = idx === 0
    const isLast = idx === chunks.length - 1
    const status = isSingle ? 0x0 : (isFirst ? 0x1 : (isLast ? 0x3 : 0x2))
    const num = chunk.length & 0xF
    const b = new Uint8Array(8)
    b[0] = (0x3 << 4) | (group & 0xF)
    b[1] = (status << 4) | num
    b.set(chunk, 2)
    const w1 = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
    const w2 = (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]
    words.push(w1 >>> 0, w2 >>> 0)
  })
  return words
}

// Vendor JSON: F0 7D 'JSON' 00 <utf8-json> F7
export function buildVendorJSON(topic: string, data: any): Uint8Array {
  const header = new Uint8Array([0xF0, 0x7D, 0x4A, 0x53, 0x4F, 0x4E, 0x00])
  const json = new TextEncoder().encode(JSON.stringify({ topic, data }))
  const tail = new Uint8Array([0xF7])
  const buf = new Uint8Array(header.length + json.length + tail.length)
  buf.set(header, 0)
  buf.set(json, header.length)
  buf.set(tail, header.length + json.length)
  return buf
}
