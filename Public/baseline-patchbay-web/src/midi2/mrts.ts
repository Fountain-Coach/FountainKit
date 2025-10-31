// Web MRTS helpers to drive the native app via MIDI 2.0 using the midi-service bridge
import { buildVendorJSON, encodeSysEx7UMP, UmpWords } from './ump'

const midiBase = () => (process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180')

export async function sendUMP(words: UmpWords, targetDisplayName = 'PatchBay Canvas') {
  const res = await fetch(`${midiBase()}/ump/send`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ target: { displayName: targetDisplayName }, words })
  })
  if (!res.ok) throw new Error(`sendUMP failed: ${res.status}`)
}

export async function vendorJSON(topic: string, data: any, targetDisplayName?: string) {
  const bytes = buildVendorJSON(topic, data)
  const words = encodeSysEx7UMP(bytes)
  await sendUMP(words, targetDisplayName)
}

export async function panByView(dx: number, dy: number, targetDisplayName?: string) {
  await vendorJSON('ui.panBy', { 'dx.view': dx, 'dy.view': dy }, targetDisplayName)
}

export async function zoomAround(anchorViewX: number, anchorViewY: number, magnification: number, targetDisplayName?: string) {
  await vendorJSON('ui.zoomAround', { 'anchor.view.x': anchorViewX, 'anchor.view.y': anchorViewY, magnification }, targetDisplayName)
}

export async function canvasReset(targetDisplayName?: string) {
  await vendorJSON('canvas.reset', {}, targetDisplayName)
}

