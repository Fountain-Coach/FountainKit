import React, { useEffect, useMemo, useRef, useState } from 'react'

type QFEvent = { event: string; note?: number; velocity?: number; value14?: number; hz?: number; channel?: number; group?: number; source?: string }

const api = {
  stream: '/api/qf/notes/stream',
  ingest: '/api/qf/notes/ingest',
}

export default function App() {
  const [events, setEvents] = useState<QFEvent[]>([])
  const [connected, setConnected] = useState(false)
  const [note, setNote] = useState(60)
  const [vel, setVel] = useState(96)
  const [hz, setHz] = useState(440)
  const [view, setView] = useState<'list'|'pianoroll'>('list')
  const [err, setErr] = useState<string|undefined>()

  // Poll SSE-like stream on an interval (sidecar repeats frames) — simple and robust
  useEffect(() => {
    let active = true
    const tick = async () => {
      try {
        const r = await fetch(api.stream, { cache: 'no-store' })
        if (!r.ok) throw new Error('SSE fetch failed: ' + r.status)
        const text = await r.text()
        const lines = text.split('\n').filter(l => l.startsWith('data:'))
        const last = lines.length ? lines[lines.length-1].slice(5).trim() : '[]'
        const arr = JSON.parse(last) as QFEvent[]
        if (!active) return
        setEvents(arr.slice(-100))
        setConnected(true)
        setErr(undefined)
      } catch (e: any) {
        if (!active) return
        setConnected(false)
        setErr(String(e?.message || e))
      }
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => { active = false; clearInterval(id) }
  }, [])

  const send = async (ev: QFEvent) => {
    await fetch(api.ingest, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(ev) })
  }

  const recent = useMemo(() => events.slice(-16).reverse(), [events])

  return (
    <div style={{ height: '100%', display: 'grid', gridTemplateRows: '48px 1fr' }}>
      <header style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 12px', borderBottom: '1px solid #E6EAF2' }}>
        <strong>QuietFrame — Web Playground</strong>
        <span style={{ opacity: .7 }}>{connected ? 'connected' : 'disconnected'} {err ? `– ${err}` : ''}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 10 }}>
          <label>note <input type="number" value={note} onChange={e => setNote(Number(e.target.value))} style={{ width: 64 }} /></label>
          <label>vel <input type="number" value={vel} onChange={e => setVel(Number(e.target.value))} style={{ width: 64 }} /></label>
          <label>hz <input type="number" value={hz} onChange={e => setHz(Number(e.target.value))} style={{ width: 90 }} /></label>
          <button onClick={() => send({ event: 'noteOn', note, velocity: vel, hz })}>Send NoteOn</button>
          <button onClick={() => send({ event: 'noteOff', note })}>Send NoteOff</button>
          <button onClick={() => setView(v => v === 'list' ? 'pianoroll' : 'list')}>{view === 'list' ? 'Piano Roll' : 'List'}</button>
        </div>
      </header>
      <main style={{ padding: 12 }}>
        {view === 'list' ? (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
            <section style={{ background: 'white', border: '1px solid #E6EAF2', borderRadius: 8, padding: 12 }}>
              <h3 style={{ margin: '0 0 8px 0', fontSize: 14 }}>Recent Events</h3>
              <div style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', fontSize: 12, lineHeight: '18px' }}>
                {recent.map((e, i) => (
                  <div key={i}>{JSON.stringify(e)}</div>
                ))}
              </div>
            </section>
            <section style={{ background: 'white', border: '1px solid #E6EAF2', borderRadius: 8, padding: 12 }}>
              <h3 style={{ margin: '0 0 8px 0', fontSize: 14 }}>Summary</h3>
              <Stats events={events} />
            </section>
          </div>
        ) : (
          <PianoRoll events={events} />
        )}
      </main>
    </div>
  )
}

function Stats({ events }: { events: QFEvent[] }) {
  const counts = useMemo(() => {
    const c: Record<string, number> = {}
    for (const e of events) c[e.event] = (c[e.event] ?? 0) + 1
    return c
  }, [events])
  return (
    <pre style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', fontSize: 12 }}>{JSON.stringify(counts, null, 2)}</pre>
  )
}

function PianoRoll({ events }: { events: QFEvent[] }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  useEffect(() => {
    const el = canvasRef.current; if (!el) return
    const ctx = el.getContext('2d')!
    const w = el.width = el.clientWidth
    const h = el.height = el.clientHeight
    ctx.clearRect(0,0,w,h)
    // Draw axes
    ctx.strokeStyle = '#E6EAF2'; ctx.lineWidth = 1
    for (let y=0; y<h; y+=24) { ctx.beginPath(); ctx.moveTo(0,y+.5); ctx.lineTo(w,y+.5); ctx.stroke() }
    const now = Date.now()
    let x = w - 4
    for (let i = events.length - 1; i >= 0 && x > 0; i--) {
      const e = events[i]
      if (e.event === 'noteOn') {
        const y = h - Math.min(h-8, Math.max(8, (e.note ?? 60) * (h/128)))
        const barH = 8
        const barW = 10 + Math.min(40, Math.max(0, (e.velocity ?? 0) / 4))
        ctx.fillStyle = '#3B82F6'
        ctx.fillRect(x - barW, y - barH/2, barW, barH)
        x -= barW + 6
      }
    }
  }, [events])
  return (
    <div style={{ background: 'white', border: '1px solid #E6EAF2', borderRadius: 8, padding: 12, height: 'calc(100vh - 120px)' }}>
      <h3 style={{ margin: '0 0 8px 0', fontSize: 14 }}>Piano Roll (recent)</h3>
      <div style={{ height: '100%', border: '1px solid #E6EAF2', borderRadius: 6 }}>
        <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />
      </div>
    </div>
  )
}

