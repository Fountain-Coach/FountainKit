import { encodeSysEx7UMP, buildVendorJSON } from '../midi2/ump'

export type Endpoint = { id: string; name: string }

const base = (path: string) => `/api/midi${path}`

export async function listEndpoints(): Promise<Endpoint[]> {
  const r = await fetch(base('/endpoints'))
  if (!r.ok) throw new Error(`GET /endpoints failed: ${r.status}`)
  return await r.json()
}

export async function sendUMP(words: number[], targetDisplayName: string) {
  const r = await fetch(base('/ump/send'), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ target: { displayName: targetDisplayName }, words }),
  })
  if (!r.ok) throw new Error(`POST /ump/send failed: ${r.status}`)
}

export async function sendVendorJSON(topic: string, data: any, targetDisplayName: string) {
  const bytes = buildVendorJSON(topic, data)
  const words = encodeSysEx7UMP(bytes)
  await sendUMP(words, targetDisplayName)
}

