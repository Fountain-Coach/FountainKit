#!/usr/bin/env node
import { panByView } from '../dist/midi2/mrts.js'

const name = process.env.TARGET_NAME || 'PatchBay Canvas'
const url = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
process.env.MIDI_SERVICE_URL = url

const dx = Number(process.env.DX || 120)
const dy = Number(process.env.DY || 80)

try {
  await panByView(dx, dy, name)
  console.log(`[mrts] panBy view=(%d,%d) sent to %s via %s`, dx, dy, name, url)
} catch (e) {
  console.error('[mrts] pan failed', e)
  process.exit(1)
}

