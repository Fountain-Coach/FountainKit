#!/usr/bin/env node
import { zoomAround } from '../dist/midi2/mrts.js'

const name = process.env.TARGET_NAME || 'PatchBay Canvas'
const url = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
process.env.MIDI_SERVICE_URL = url

const ax = Number(process.env.AX || 512)
const ay = Number(process.env.AY || 384)
const mag = Number(process.env.MAG || 0.2)

try {
  await zoomAround(ax, ay, mag, name)
  console.log(`[mrts] zoomAround anchor=(%d,%d) mag=%d sent to %s via %s`, ax, ay, mag, name, url)
} catch (e) {
  console.error('[mrts] zoom failed', e)
  process.exit(1)
}

