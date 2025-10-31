#!/usr/bin/env node
const MIDI_SERVICE_URL = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
const TARGET_NAME = process.env.TARGET_NAME || 'Headless Canvas'
const AX = Number(process.env.AX || 512)
const AY = Number(process.env.AY || 384)
const MAG = Number(process.env.MAG || 0.2)
const PAN_DX = Number(process.env.DX || 120)
const PAN_DY = Number(process.env.DY || 80)
const EPS = Number(process.env.EPS || 1.0)

const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const mrts = await import('../dist/midi2/mrts.js')

async function flush() { await fetch(`${MIDI_SERVICE_URL}/ump/flush`, { method: 'POST' }).catch(()=>{}) }
async function tail(limit = 256) {
  const r = await fetch(`${MIDI_SERVICE_URL}/ump/tail`)
  if (!r.ok) throw new Error(`tail failed: ${r.status}`)
  const j = await r.json(); return (j.events || [])
}
function parseSnapshot(events) {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i]; if (e.peJSON) { try { const obj = JSON.parse(e.peJSON); const props = (obj.properties || []).reduce((acc, it) => { acc[it.name] = it.value; return acc }, {}); return { ts: e.ts, props } } catch {} }
  }
  return null
}
function docToView(x, y, z, tx, ty) { return { x: (x + tx) * z, y: (y + ty) * z } }
function viewToDoc(x, y, z, tx, ty) { return { x: (x / z) - tx, y: (y / z) - ty } }
async function waitForSnapshot(prevTs = 0, tries = 10) {
  for (let i = 0; i < tries; i++) { const ev = await tail(); const snap = parseSnapshot(ev); if (snap && snap.ts > prevTs) return snap; await sleep(100) }
  throw new Error('snapshot timeout')
}
async function main() {
  console.log('[assert] MIDI_SERVICE_URL=%s target=%s', MIDI_SERVICE_URL, TARGET_NAME)
  await flush(); await mrts.canvasReset(TARGET_NAME)
  let snap = await waitForSnapshot(0)
  let z = Number(snap.props['zoom'] ?? 1), tx = Number(snap.props['translation.x'] ?? 0), ty = Number(snap.props['translation.y'] ?? 0)
  await mrts.panByView(PAN_DX, PAN_DY, TARGET_NAME)
  snap = await waitForSnapshot(snap.ts)
  const z2 = Number(snap.props['zoom'] ?? z), tx2 = Number(snap.props['translation.x'] ?? tx), ty2 = Number(snap.props['translation.y'] ?? ty)
  const expTx = tx + (PAN_DX / z), expTy = ty + (PAN_DY / z)
  if (Math.abs(tx2 - expTx) > EPS) throw new Error(`pan tx mismatch: got ${tx2} expected ${expTx}`)
  if (Math.abs(ty2 - expTy) > EPS) throw new Error(`pan ty mismatch: got ${ty2} expected ${expTy}`)
  const anchorDoc = viewToDoc(AX, AY, z2, tx2, ty2)
  await mrts.zoomAround(AX, AY, MAG, TARGET_NAME)
  snap = await waitForSnapshot(snap.ts)
  const z3 = Number(snap.props['zoom'] ?? z2), tx3 = Number(snap.props['translation.x'] ?? tx2), ty3 = Number(snap.props['translation.y'] ?? ty2)
  const newView = docToView(anchorDoc.x, anchorDoc.y, z3, tx3, ty3)
  const drift = Math.hypot(newView.x - AX, newView.y - AY)
  if (drift > EPS) throw new Error(`anchor drift ${drift} > ${EPS}`)
  console.log('[assert] OK: pan and anchor-stable zoom invariants pass (eps=%s)', EPS)
}
main().catch(e => { console.error('[assert] failed', e); process.exit(1) })
