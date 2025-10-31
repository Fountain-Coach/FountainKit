import React, { useEffect, useMemo, useRef, useState } from 'react'
import { getCanvas, panBy, zoomSet, resetTransform } from '../ws/patchbay'
import { listEndpoints, sendVendorJSON } from '../ws/midi'
import { drawGrid } from './Grid'

export default function App() {
  const [scale, setScale] = useState(1)
  const [tx, setTx] = useState(0)
  const [ty, setTy] = useState(0)
  const [gridStep, setGridStep] = useState(24)
  const [loading, setLoading] = useState(true)
  const [driveMode, setDriveMode] = useState<'rest' | 'midi'>('midi')
  const [endpoints, setEndpoints] = useState<{ id: string; name: string }[]>([])
  const [target, setTarget] = useState<string>('PatchBay Canvas')
  const [log, setLog] = useState<string[]>([])
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

  useEffect(() => {
    (async () => {
      try {
        const eps = await listEndpoints()
        setEndpoints(eps)
        const canvas = eps.find(e => e.name.includes('PatchBay Canvas'))
        if (canvas) setTarget(canvas.name)
      } catch (e) {
        console.warn('midi-service not reachable; MIDI drive disabled', e)
        setDriveMode('rest')
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
        if (driveMode === 'midi') {
          await sendVendorJSON('ui.zoomAround', { 'anchor.view.x': e.nativeEvent.offsetX, 'anchor.view.y': e.nativeEvent.offsetY, magnification: newScale / scale - 1 }, target)
        } else {
          await zoomSet({ scale: newScale, anchorView: { x: e.nativeEvent.offsetX, y: e.nativeEvent.offsetY } })
        }
        setLog(l => [`zoomAround z=${newScale.toFixed(2)} anchor=(${e.nativeEvent.offsetX.toFixed(0)},${e.nativeEvent.offsetY.toFixed(0)})`, ...l].slice(0, 6))
      } catch {}
    } else {
      // pan
      const dx = -e.deltaX / scale
      const dy = -e.deltaY / scale
      setTx((v) => v + dx)
      setTy((v) => v + dy)
      try {
        if (driveMode === 'midi') {
          await sendVendorJSON('ui.panBy', { 'dx.view': -e.deltaX, 'dy.view': -e.deltaY }, target)
        } else {
          await panBy({ dx, dy })
        }
        setLog(l => [`pan dx=${(-e.deltaX).toFixed(1)} dy=${(-e.deltaY).toFixed(1)}`, ...l].slice(0, 6))
      } catch {}
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
    try {
      if (driveMode === 'midi') {
        await sendVendorJSON('ui.panBy', { 'dx.view': dxView, 'dy.view': dyView }, target)
      } else {
        await panBy({ dx, dy })
      }
    } catch {}
  }

  const doReset = async () => {
    const { dx, dy, nextScale } = resetTransform(scale, tx, ty)
    setScale(nextScale)
    setTx((v) => v + dx)
    setTy((v) => v + dy)
    try {
      if (driveMode === 'midi') {
        await sendVendorJSON('canvas.reset', {}, target)
      } else {
        await panBy({ dx, dy }); await zoomSet({ scale: nextScale })
      }
      setLog(l => ["reset", ...l].slice(0, 6))
    } catch {}
  }

  return (
    <div style={{ height: '100%', display: 'grid', gridTemplateRows: '48px 1fr' }}>
      <header style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 12px', borderBottom: '1px solid #E6EAF2' }}>
        <strong>Baseline‑PatchBay (Web)</strong>
        <span style={{ opacity: 0.7 }}>zoom={scale.toFixed(2)} tx={tx.toFixed(1)} ty={ty.toFixed(1)} step={gridStep}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 8 }}>
          <label style={{ fontSize: 12, opacity: 0.7 }}>Drive:</label>
          <select value={driveMode} onChange={(e) => setDriveMode(e.target.value as any)}>
            <option value="midi">MIDI 2.0</option>
            <option value="rest">REST</option>
          </select>
          {driveMode === 'midi' && (
            <select value={target} onChange={(e) => setTarget(e.target.value)}>
              {[target, ...endpoints.map(e => e.name)].filter((v, i, a) => a.indexOf(v) === i).map(n => (
                <option key={n} value={n}>{n}</option>
              ))}
            </select>
          )}
          <button onClick={doReset}>Reset</button>
        </div>
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
        <div style={{ position: 'absolute', right: 8, top: 8, background: 'rgba(255,255,255,0.9)', border: '1px solid #E6EAF2', borderRadius: 6, padding: '6px 8px', fontSize: 12, minWidth: 240 }}>
          <div style={{ fontWeight: 600, marginBottom: 4 }}>MIDI 2.0 Monitor</div>
          <div style={{ opacity: 0.7, marginBottom: 4 }}>mode: {driveMode.toUpperCase()} target: {target}</div>
          {log.slice(0, 5).map((l, i) => (
            <div key={i} style={{ whiteSpace: 'pre' }}>{l}</div>
          ))}
        </div>
      </div>
    </div>
  )
}
