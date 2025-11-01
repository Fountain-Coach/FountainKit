#!/usr/bin/env node
const TARGET_NAME = process.env.TARGET_NAME || 'Flow'
const MIDI_SERVICE_URL = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const mrts = await import('../dist/midi2/mrts.js')

async function tail(limit = 256) {
  const r = await fetch(`${MIDI_SERVICE_URL}/ump/tail`)
  if (!r.ok) throw new Error(`tail failed: ${r.status}`)
  const j = await r.json(); return (j.events || [])
}

function latestVendor(events, type) {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i]
    if (!e.vendorJSON) continue
    try { const obj = JSON.parse(e.vendorJSON); if (obj.type === type) return obj } catch {}
  }
  return null
}

async function main() {
  console.log('[flow] MIDI_SERVICE_URL=%s target=%s', MIDI_SERVICE_URL, TARGET_NAME)
  await fetch(`${MIDI_SERVICE_URL}/ump/flush`, { method: 'POST' }).catch(()=>{})

  // Ensure nodes for Editor, Corpus, Submit transform exist
  await mrts.vendorJSON('flow.node.add', { nodeId: 'n-editor', displayName: 'Fountain Editor', product: 'FountainEditor' }, TARGET_NAME)
  await mrts.vendorJSON('flow.node.add', { nodeId: 'n-corpus', displayName: 'Corpus Instrument', product: 'CorpusInstrument' }, TARGET_NAME)
  await mrts.vendorJSON('flow.node.add', { nodeId: 'n-submit', displayName: 'Submit', product: 'Submit' }, TARGET_NAME)

  // Create noodle: editor.text.content.out -> Submit.out -> Corpus.baseline.add.in
  await mrts.vendorJSON('flow.edge.create', { from: { node: 'n-editor', port: 'text.content.out' }, to: { node: 'n-corpus', port: 'baseline.add.in' }, transformId: 'n-submit' }, TARGET_NAME)

  // Drive editor.submit (the Editor headless will route via Flow if present)
  const sample = `INT. ROOM — DAY\nJOHN\n(whispering)\nHello.\nHe sits.\n`
  await mrts.vendorJSON('text.set', { text: sample, cursor: sample.length }, 'Fountain Editor')
  await mrts.vendorJSON('editor.submit', { text: sample }, 'Fountain Editor')
  await sleep(150)

  const events = await tail()
  const added = latestVendor(events, 'corpus.baseline.added')
  if (!added) throw new Error('no corpus.baseline.added after flow submit')
  console.log('[flow] OK: baseline added baselineId=%s lines=%s chars=%s', added.baselineId, added.lines, added.chars)
}

main().catch(e => { console.error('[flow] failed', e); process.exit(1) })

