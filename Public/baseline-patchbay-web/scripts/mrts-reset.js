#!/usr/bin/env node
import { canvasReset } from '../dist/midi2/mrts.js'

const name = process.env.TARGET_NAME || 'PatchBay Canvas'
const url = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
process.env.MIDI_SERVICE_URL = url

try {
  await canvasReset(name)
  console.log(`[mrts] reset sent to ${name} via ${url}`)
} catch (e) {
  console.error('[mrts] reset failed', e)
  process.exit(1)
}

