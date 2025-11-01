#!/usr/bin/env node
const TARGET = process.env.TARGET_NAME || 'Flow'
const URL = process.env.MIDI_SERVICE_URL || 'http://127.0.0.1:7180'
const sleep = (ms) => new Promise(r => setTimeout(r, ms))
const mrts = await import('../dist/midi2/mrts.js')

async function tail(limit = 256) {
  const r = await fetch(`${URL}/ump/tail`)
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
  console.log('[flow-llm] URL=%s target=%s', URL, TARGET)
  await fetch(`${URL}/ump/flush`, { method: 'POST' }).catch(()=>{})
  // Ensure nodes exist
  await mrts.vendorJSON('flow.node.add', { nodeId: 'n-editor', displayName: 'Fountain Editor', product: 'FountainEditor' }, TARGET)
  await mrts.vendorJSON('flow.node.add', { nodeId: 'n-llm', displayName: 'LLM Adapter', product: 'LLMAdapter' }, TARGET)
  await mrts.vendorJSON('flow.edge.create', { from: { node: 'n-editor', port: 'text.content.out' }, to: { node: 'n-llm', port: 'prompt.in' } }, TARGET)
  // Drive via Flow
  const text = 'Hello from Flow to LLM'
  await mrts.vendorJSON('flow.forward.test', { from: { node: 'n-editor', port: 'text.content.out' }, payload: { kind: 'text', text } }, TARGET)
  await sleep(150)
  const events = await tail()
  const started = latestVendor(events, 'llm.chat.started')
  const completed = latestVendor(events, 'llm.chat.completed')
  if (!started || !completed) throw new Error('missing llm.chat monitors from flow forward')
  console.log('[flow-llm] OK: flow forwarded → llm chat monitors present')
}

main().catch(e => { console.error('[flow-llm] failed', e); process.exit(1) })

