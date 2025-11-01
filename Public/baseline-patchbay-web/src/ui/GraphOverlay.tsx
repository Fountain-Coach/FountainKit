import React, { useEffect, useMemo, useState } from 'react'

type Graph = { nodes: { id: string, displayName: string, product: string }[], edges: { id: string, from: { node: string, port: string }, to: { node: string, port: string }, transformId?: string }[] }

export default function GraphOverlay({ scale, tx, ty }: { scale: number, tx: number, ty: number }) {
  const [graph, setGraph] = useState<Graph | null>(null)
  useEffect(() => {
    (async () => {
      try {
        const r = await fetch('/api/midi/flow/graph')
        if (r.ok) {
          const j = await r.json()
          setGraph(j)
        }
      } catch {}
    })()
  }, [])
  const positions = useMemo(() => {
    // Fixed positions for default template; unknown nodes stacked
    const map: Record<string, { x: number, y: number }> = {}
    if (!graph) return map
    for (const n of graph.nodes) {
      const key = n.id
      switch (n.displayName) {
        case 'Fountain Editor': map[key] = { x: 100, y: 100 }; break
        case 'Submit': map[key] = { x: 380, y: 120 }; break
        case 'Corpus Instrument': map[key] = { x: 640, y: 100 }; break
        case 'LLM Adapter': map[key] = { x: 640, y: 280 }; break
        default:
          map[key] = { x: 120 + Object.keys(map).length * 80, y: 360 }
      }
    }
    return map
  }, [graph])

  if (!graph) return null
  return (
    <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
      <svg width="100%" height="100%" style={{ position: 'absolute', inset: 0, transform: `translate(${tx}px, ${ty}px) scale(${scale})`, transformOrigin: '0 0' }}>
        {graph.edges.map(e => {
          const a = positions[e.from.node]; const b = positions[e.to.node]
          if (!a || !b) return null
          const x1 = a.x + 120, y1 = a.y + 20
          const x2 = b.x, y2 = b.y + 20
          const mx = (x1 + x2) / 2
          const d = `M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`
          return <path key={e.id} d={d} stroke="#6B8AF7" strokeWidth={2} fill="none" opacity={0.8} />
        })}
      </svg>
      {graph.nodes.map(n => {
        const p = positions[n.id]; if (!p) return null
        return (
          <div key={n.id} style={{ position: 'absolute', left: 0, top: 0, transform: `translate(${(p.x + tx) * scale}px, ${(p.y + ty) * scale}px)`, transformOrigin: '0 0', width: 120 * scale, height: 40 * scale, pointerEvents: 'none' }}>
            <div style={{ background: 'white', border: '1px solid #E6EAF2', borderRadius: 6, boxShadow: '0 1px 3px rgba(0,0,0,0.06)', padding: 6 * scale, fontSize: 12 * scale, textAlign: 'center' }}>{n.displayName}</div>
          </div>
        )
      })}
    </div>
  )
}

