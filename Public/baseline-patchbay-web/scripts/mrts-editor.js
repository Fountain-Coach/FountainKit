#!/usr/bin/env node
const TARGET_NAME = process.env.TARGET_NAME || 'Fountain Editor'
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
  console.log('[editor] MIDI_SERVICE_URL=%s target=%s', MIDI_SERVICE_URL, TARGET_NAME)
  // Clear recorder
  await fetch(`${MIDI_SERVICE_URL}/ump/flush`, { method: 'POST' }).catch(()=>{})

  // Step 1: Reset + A4 (text.clear)
  await mrts.vendorJSON('text.clear', {}, TARGET_NAME)
  await sleep(100)
  // Step 2: Typing baseline (text.set)
  const sample = `INT. ROOM — DAY\nJOHN\n(whispering)\nHello.\nHe sits.\n`
  await mrts.vendorJSON('text.set', { text: sample, cursor: sample.length }, TARGET_NAME)
  await sleep(150)
  // Step 3: Agent suggestion and apply
  await mrts.vendorJSON('agent.suggest', { id: 's1', text: '\nCUT TO:', policy: 'append' }, TARGET_NAME)
  await sleep(50)
  await mrts.vendorJSON('suggestion.apply', { id: 's1' }, TARGET_NAME)
  await sleep(100)
  // Step 4: Awareness/memory examples
  await mrts.vendorJSON('awareness.setCorpus', { corpusId: 'fountain-editor' }, TARGET_NAME)
  await mrts.vendorJSON('memory.inject.drifts', { items: [{ id: 'd1', text: 'drift' }] }, TARGET_NAME)
  await sleep(100)

  const events = await tail()
  const parsed = latestVendor(events, 'text.parsed')
  if (!parsed) throw new Error('no text.parsed event found')
  console.log('[editor] OK: text.parsed lines=%s chars=%s wrapColumn=%s', parsed.lines, parsed.chars, parsed.wrapColumn)
}

main().catch(e => { console.error('[editor] failed', e); process.exit(1) })

