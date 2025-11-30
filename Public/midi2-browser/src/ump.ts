export function bytesToWords(bytes: number[]): number[] {
  const words: number[] = []
  for (let i = 0; i < bytes.length; i += 4) {
    const b0 = bytes[i] ?? 0
    const b1 = bytes[i + 1] ?? 0
    const b2 = bytes[i + 2] ?? 0
    const b3 = bytes[i + 3] ?? 0
    const word = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    words.push(word >>> 0)
  }
  return words
}
