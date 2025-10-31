#!/usr/bin/env node
import { spawn } from 'node:child_process'

const run = (cmd, args, opts = {}) => new Promise((resolve, reject) => {
  const p = spawn(cmd, args, { stdio: ['ignore','pipe','inherit'], ...opts })
  let out = ''
  p.stdout.on('data', (d) => { out += d.toString('utf8') })
  p.on('exit', (code) => code === 0 ? resolve(out) : reject(new Error(`${cmd} exited ${code}`)))
})

const root = process.cwd() + '/..'
const MIDI_SERVICE_URL = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
const TARGET_NAME = process.env.TARGET_NAME || 'Headless Canvas'
process.env.MIDI_SERVICE_URL = MIDI_SERVICE_URL

// Dist modules (built via `npm run build`)
const mrts = await import('../dist/midi2/mrts.js')

async function readFacts() {
  try {
    const text = await run('swift', ['run', '--package-path', 'Packages/FountainApps', 'store-dump'], { cwd: root })
    return JSON.parse(text)
  } catch (e) {
    console.warn('[mrts] facts not available; using defaults', e.message)
    return {
      pe: ['grid.minor','grid.majorEvery','zoom','translation.x','translation.y'],
      vendorJSON: ['ui.panBy','ui.zoomAround','canvas.reset']
    }
  }
}

async function main() {
  console.log(`[mrts] MIDI_SERVICE_URL=${MIDI_SERVICE_URL} target=${TARGET_NAME}`)
  const facts = await readFacts()

  console.log('[mrts] reset')
  await mrts.canvasReset(TARGET_NAME)

  // Pan by view deltas (matches TrackpadBehaviorRobotTests subset)
  const panDx = Number(process.env.DX || 120)
  const panDy = Number(process.env.DY || 80)
  console.log('[mrts] panBy view=(%d,%d)', panDx, panDy)
  await mrts.panByView(panDx, panDy, TARGET_NAME)

  // Zoom around an anchor with 20% magnification
  const ax = Number(process.env.AX || 512)
  const ay = Number(process.env.AY || 384)
  const mag = Number(process.env.MAG || 0.2)
  console.log('[mrts] zoomAround anchor=(%d,%d) mag=%s', ax, ay, mag)
  await mrts.zoomAround(ax, ay, mag, TARGET_NAME)

  console.log('[mrts] done')
}

main().catch((e) => { console.error('[mrts] failed', e); process.exit(1) })
