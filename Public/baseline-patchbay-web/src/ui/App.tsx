import React, { useEffect, useMemo, useRef, useState } from 'react'
import { getCanvas, panBy, zoomSet, resetTransform } from '../ws/patchbay'
import { drawGrid } from './Grid'

export default function App() {
  const [scale, setScale] = useState(1)
  const [tx, setTx] = useState(0)
  const [ty, setTy] = useState(0)
  const [gridStep, setGridStep] = useState(24)
  const [loading, setLoading] = useState(true)
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const dpr = useMemo(() => window.devicePixelRatio || 1, [])

  // Initial load from server
  useEffect(() => {
    (async () => {
      try {
        const c = await getCanvas()
        setScale(c.transform.scale)
        setTx(c.transform.translation.x)
        setTy(c.transform.translation.y)
        setGridStep(c.gridStep ?? 24)
      } catch (e) {
        console.warn('patchbay not reachable, using defaults', e)
      } finally {
        setLoading(false)
      }
    })()
  }, [])

  // Draw
  useEffect(() => {
    const el = canvasRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    el.width = Math.floor(rect.width * dpr)
    el.height = Math.floor(rect.height * dpr)
    const ctx = el.getContext('2d')!
    ctx.save()
    ctx.scale(dpr, dpr)
    ctx.clearRect(0, 0, rect.width, rect.height)
    drawGrid(ctx, rect.width, rect.height, { step: gridStep, scale, tx, ty })
    ctx.restore()
  }, [scale, tx, ty, gridStep, dpr])

  // Interaction
  const onWheel: React.WheelEventHandler<HTMLCanvasElement> = async (e) => {
    if (e.ctrlKey) {
      e.preventDefault()
      const factor = e.deltaY < 0 ? 1.1 : 0.9
      const newScale = Math.min(16, Math.max(0.1, scale * factor))
      setScale(newScale)
      try {
        await zoomSet({ scale: newScale, anchorView: { x: e.nativeEvent.offsetX, y: e.nativeEvent.offsetY } })
      } catch {}
    } else {
      // pan
      const dx = -e.deltaX / scale
      const dy = -e.deltaY / scale
      setTx((v) => v + dx)
      setTy((v) => v + dy)
      try { await panBy({ dx, dy }) } catch {}
    }
  }

  let lastDrag: { x: number; y: number } | null = null
  const onMouseDown: React.MouseEventHandler<HTMLCanvasElement> = (e) => {
    lastDrag = { x: e.clientX, y: e.clientY }
  }
  const onMouseUp: React.MouseEventHandler<HTMLCanvasElement> = () => { lastDrag = null }
  const onMouseMove: React.MouseEventHandler<HTMLCanvasElement> = async (e) => {
    if (!lastDrag) return
    const dxView = e.clientX - lastDrag.x
    const dyView = e.clientY - lastDrag.y
    lastDrag = { x: e.clientX, y: e.clientY }
    const dx = dxView / scale
    const dy = dyView / scale
    setTx((v) => v + dx)
    setTy((v) => v + dy)
    try { await panBy({ dx, dy }) } catch {}
  }

  const doReset = async () => {
    const { dx, dy, nextScale } = resetTransform(scale, tx, ty)
    setScale(nextScale)
    setTx((v) => v + dx)
    setTy((v) => v + dy)
    try { await panBy({ dx, dy }); await zoomSet({ scale: nextScale }) } catch {}
  }

  return (
    <div style={{ height: '100%', display: 'grid', gridTemplateRows: '48px 1fr' }}>
      <header style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 12px', borderBottom: '1px solid #E6EAF2' }}>
        <strong>Baseline‑PatchBay (Web)</strong>
        <span style={{ opacity: 0.7 }}>zoom={scale.toFixed(2)} tx={tx.toFixed(1)} ty={ty.toFixed(1)} step={gridStep}</span>
        <button onClick={doReset} style={{ marginLeft: 'auto' }}>Reset</button>
      </header>
      <div style={{ position: 'relative' }}>
        {loading && <div style={{ position: 'absolute', top: 8, left: 8, opacity: 0.6 }}>Loading canvas…</div>}
        <canvas
          ref={canvasRef}
          onWheel={onWheel}
          onMouseDown={onMouseDown}
          onMouseUp={onMouseUp}
          onMouseLeave={onMouseUp}
          onMouseMove={onMouseMove}
          style={{ width: '100%', height: '100%', display: 'block', cursor: 'grab' }}
        />
        {/* Simple monitor */}
        <div style={{ position: 'absolute', right: 8, top: 8, background: 'rgba(255,255,255,0.9)', border: '1px solid #E6EAF2', borderRadius: 6, padding: '6px 8px', fontSize: 12 }}>
          <div style={{ fontWeight: 600, marginBottom: 4 }}>MIDI 2.0 Monitor</div>
          <div>ui.zoomAround / ui.panBy mirrored to REST</div>
        </div>
      </div>
    </div>
  )
}

