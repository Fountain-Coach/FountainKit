import React, { useEffect, useMemo, useRef, useState } from 'react'
import { listEndpoints, sendVendorJSON } from '../ws/midi'

type ParsedMeta = { lines: number; chars: number; wrapColumn?: number }

async function umpTail(): Promise<any[]> {
  try {
    const r = await fetch('/api/midi/ump/tail')
    if (!r.ok) return []
    const j = await r.json()
    return j.events || []
  } catch {
    return []
  }
}

function parseLatestTextParsed(events: any[]): ParsedMeta | null {
  for (let i = events.length - 1; i >= 0; i--) {
    const e = events[i]
    const v = e && e.vendorJSON
    if (!v) continue
    try {
      const obj = JSON.parse(v)
      if (obj && obj.type === 'text.parsed') {
        return { lines: Number(obj.lines || 0), chars: Number(obj.chars || 0), wrapColumn: Number(obj.wrapColumn || 0) }
      }
    } catch {}
  }
  return null
}

export default function FountainEditor() {
  const [text, setText] = useState('')
  const [editing, setEditing] = useState(false)
  const [metrics, setMetrics] = useState<ParsedMeta>({ lines: 0, chars: 0, wrapColumn: undefined })
  const [endpoints, setEndpoints] = useState<{ id: string; name: string }[]>([])
  const [target, setTarget] = useState('Fountain Editor')
  const typingTimer = useRef<number | null>(null)

  useEffect(() => {
    (async () => {
      try {
        const eps = await listEndpoints()
        setEndpoints(eps)
        const ed = eps.find(e => e.name.includes('Fountain Editor'))
        if (ed) setTarget(ed.name)
      } catch {}
    })()
  }, [])

  const scheduleSend = (t: string) => {
    if (typingTimer.current) window.clearTimeout(typingTimer.current)
    typingTimer.current = window.setTimeout(async () => {
      try {
        await sendVendorJSON('text.set', { text: t, cursor: t.length }, target)
        // Pull latest parsed snapshot
        const ev = await umpTail()
        const m = parseLatestTextParsed(ev)
        if (m) setMetrics(m)
      } catch {}
    }, 120)
  }

  const onChange: React.ChangeEventHandler<HTMLTextAreaElement> = (e) => {
    const val = e.target.value
    setText(val)
    scheduleSend(val)
  }

  const clear = async () => {
    setText('')
    try {
      await sendVendorJSON('text.clear', {}, target)
      const ev = await umpTail(); const m = parseLatestTextParsed(ev); if (m) setMetrics(m)
    } catch {}
  }

  const suggest = async () => {
    try {
      await sendVendorJSON('agent.suggest', { id: 's1', text: '\nCUT TO:', policy: 'append' }, target)
    } catch {}
  }

  const apply = async () => {
    try {
      await sendVendorJSON('suggestion.apply', { id: 's1' }, target)
      const ev = await umpTail(); const m = parseLatestTextParsed(ev); if (m) setMetrics(m)
    } catch {}
  }

  const fontStack = '"Courier Prime", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace'

  return (
    <div style={{ border: '1px solid #E6EAF2', borderRadius: 6, padding: 8 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <div style={{ fontSize: 12, fontWeight: 600 }}>Fountain Editor</div>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6 }}>
          <select value={target} onChange={(e) => setTarget(e.target.value)}>
            {[target, ...endpoints.map(e => e.name)].filter((v, i, a) => a.indexOf(v) === i).map(n => (
              <option key={n} value={n}>{n}</option>
            ))}
          </select>
          <button onClick={clear}>Clear</button>
          <button onClick={suggest}>Suggest</button>
          <button onClick={apply}>Apply</button>
        </div>
      </div>
      {(!editing && text.length === 0) ? (
        <div onClick={() => setEditing(true)} style={{ background: '#F5F7FA', borderRadius: 8, overflow: 'hidden', position: 'relative', cursor: 'text' }}>
          <div style={{ height: 12 }} />
          <div style={{ margin: '0 auto', width: 595, height: 842, background: 'white', borderRadius: 8, boxShadow: '0 8px 24px rgba(0,0,0,0.08)' }} />
          <div style={{ position: 'absolute', top: 8, left: 8, fontSize: 11, opacity: 0.6 }}>Click to start typing…</div>
        </div>
      ) : (
        <textarea value={text} onChange={onChange} spellCheck={false}
          style={{ width: '100%', minHeight: 180, fontFamily: fontStack, fontSize: 12, lineHeight: '1.1', whiteSpace: 'pre', padding: 8, border: '1px solid #E6EAF2', borderRadius: 4 }} />
      )}
      <div style={{ display: 'flex', gap: 12, fontSize: 11, opacity: 0.7, marginTop: 4 }}>
        <div>lines: {metrics.lines}</div>
        <div>chars: {metrics.chars}</div>
        {metrics.wrapColumn ? <div>wrapColumn: {metrics.wrapColumn}</div> : null}
      </div>
    </div>
  )
}
