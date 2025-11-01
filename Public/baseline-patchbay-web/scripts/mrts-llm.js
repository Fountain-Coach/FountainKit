#!/usr/bin/env node
const TARGET_NAME = process.env.TARGET_NAME || 'LLM Adapter'
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
  console.log('[llm] MIDI_SERVICE_URL=%s target=%s', MIDI_SERVICE_URL, TARGET_NAME)
  await fetch(`${MIDI_SERVICE_URL}/ump/flush`, { method: 'POST' }).catch(()=>{})
  await mrts.vendorJSON('llm.set', { provider: 'openai', model: 'gpt-4o-mini', streaming: false }, TARGET_NAME)
  await mrts.vendorJSON('llm.chat', { messages: [{ role: 'user', content: 'Hello' }] }, TARGET_NAME)
  await sleep(100)
  const events = await tail()
  const started = latestVendor(events, 'llm.chat.started')
  const completed = latestVendor(events, 'llm.chat.completed')
  if (!started || !completed) throw new Error('missing llm.chat monitor events')
  console.log('[llm] OK: started(provider=%s,model=%s) → completed(%s chars)', started.provider, started.model, completed['answer.chars'])
}

main().catch(e => { console.error('[llm] failed', e); process.exit(1) })

