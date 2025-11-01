import React, { useEffect, useMemo, useRef, useState } from 'react'
import { getCanvas, panBy, zoomSet, resetTransform } from '../ws/patchbay'
import { listEndpoints, sendVendorJSON, peSetProperties } from '../ws/midi'
import { drawGrid } from './Grid'
import FountainEditor from '../editor/FountainEditor'
import GraphOverlay from './GraphOverlay'

export default function App() {
  // Layout state (three panes)
  const containerRef = useRef<HTMLDivElement | null>(null)
  const [containerW, setContainerW] = useState(1200)
  const [leftFrac, setLeftFrac] = useState(0.22)
  const [rightFrac, setRightFrac] = useState(0.26)
  const MIN_PX = 160
  const GUTTER = 6
  useEffect(() => {
    const update = () => {
      if (containerRef.current) {
        setContainerW(containerRef.current.getBoundingClientRect().width)
      }
    }
    update()
    window.addEventListener('resize', update)
    return () => window.removeEventListener('resize', update)
  }, [])
  // Compute clamped widths
  const leftW = Math.max(MIN_PX, Math.min(containerW - MIN_PX * 2 - GUTTER * 2, leftFrac * containerW))
  const rightW = Math.max(MIN_PX, Math.min(containerW - leftW - MIN_PX - GUTTER * 2, rightFrac * containerW))
  const centerW = Math.max(MIN_PX, containerW - leftW - rightW - GUTTER * 2)
  // Gutter dragging
  const dragState = useRef<{ which: 'left' | 'right' | null } | null>({ which: null })
  useEffect(() => {
    const onMove = (e: MouseEvent) => {
      if (!dragState.current || !dragState.current.which) return
      if (!containerRef.current) return
      const rect = containerRef.current.getBoundingClientRect()
      const relX = e.clientX - rect.left
      if (dragState.current.which === 'left') {
        const newLeft = Math.max(MIN_PX, Math.min(containerW - MIN_PX * 2 - GUTTER * 2, relX))
        const lf = newLeft / containerW
        setLeftFrac(lf)
        setLog(l => [`ui.layout.changed left.frac=${lf.toFixed(3)} right.frac=${rightFrac.toFixed(3)}`, ...l].slice(0, 6))
        if (driveMode === 'midi') {
          sendVendorJSON('ui.layout.changed', { 'left.frac': lf, 'right.frac': rightFrac }, target).catch(()=>{})
          if (syncPE) { peSetProperties({ 'layout.left.frac': lf, 'layout.right.frac': rightFrac }, target).catch(()=>{}) }
        }
      } else {
        const newRight = Math.max(MIN_PX, Math.min(containerW - leftW - MIN_PX - GUTTER * 2, containerW - GUTTER - relX))
        const rf = newRight / containerW
        setRightFrac(rf)
        setLog(l => [`ui.layout.changed left.frac=${leftFrac.toFixed(3)} right.frac=${rf.toFixed(3)}`, ...l].slice(0, 6))
        if (driveMode === 'midi') {
          sendVendorJSON('ui.layout.changed', { 'left.frac': leftFrac, 'right.frac': rf }, target).catch(()=>{})
          if (syncPE) { peSetProperties({ 'layout.left.frac': leftFrac, 'layout.right.frac': rf }, target).catch(()=>{}) }
        }
      }
    }
    const onUp = () => { if (dragState.current) dragState.current.which = null }
    window.addEventListener('mousemove', onMove)
    window.addEventListener('mouseup', onUp)
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp) }
  }, [containerW, leftW])

  // Pane items (DnD) — mirror baseline behaviors
  const [leftItems, setLeftItems] = useState<string[]>(Array.from({ length: 12 }, (_, i) => `Item #${i}`))
  const [rightItems, setRightItems] = useState<string[]>(Array.from({ length: 6 }, (_, i) => `Log #${i}`))
  const onDragStart = (id: string, from: 'left' | 'right') => (e: React.DragEvent) => {
    e.dataTransfer.setData('text/plain', id)
    setLog(l => [`ui.dnd.begin item=${id} source=${from}`, ...l].slice(0, 6))
  }
  const onDragOver: React.DragEventHandler = (e) => { e.preventDefault() }
  const onDropList = (side: 'left' | 'right') => (e: React.DragEvent) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    if (!id) return
    if (side === 'left') {
      setRightItems((r) => r.filter(x => x !== id))
      setLeftItems((l) => (l.includes(id) ? l : [...l, id]))
    } else {
      setLeftItems((l) => l.filter(x => x !== id))
      setRightItems((r) => (r.includes(id) ? r : [...r, id]))
    }
    setLog(l => [`ui.dnd.drop item=${id} target=${side}`, ...l].slice(0, 6))
  }
  const onDropCenter: React.DragEventHandler = (e) => {
    e.preventDefault()
    const id = e.dataTransfer.getData('text/plain')
    if (id) setLog(l => [`ui.dnd.drop item=${id} target=center`, ...l].slice(0, 6))
  }
  const [scale, setScale] = useState(1)
  const [tx, setTx] = useState(0)
  const [ty, setTy] = useState(0)
  const [gridStep, setGridStep] = useState(24)
  const [loading, setLoading] = useState(true)
  const [driveMode, setDriveMode] = useState<'rest' | 'midi'>('midi')
  const [endpoints, setEndpoints] = useState<{ id: string; name: string }[]>([])
  const [target, setTarget] = useState<string>('PatchBay Canvas')
  const [log, setLog] = useState<string[]>([])
  const [syncPE, setSyncPE] = useState(true)
  const [health, setHealth] = useState<{ patchbay?: 'ok'|'bad', midi?: 'ok'|'bad' }>({})
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

  useEffect(() => {
    (async () => {
      try {
        const r1 = await fetch('/api/patchbay/health'); setHealth(h => ({...h, patchbay: r1.ok ? 'ok' : 'bad'}))
      } catch { setHealth(h => ({...h, patchbay: 'bad'})) }
      try {
        const r2 = await fetch('/api/midi/health'); setHealth(h => ({...h, midi: r2.ok ? 'ok' : 'bad'}))
      } catch { setHealth(h => ({...h, midi: 'bad'})) }
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
          if (syncPE) { await peSetProperties({ 'zoom': newScale }, target) }
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
          if (syncPE) { await peSetProperties({ 'translation.x': tx + dx, 'translation.y': ty + dy }, target) }
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
        if (syncPE) { await peSetProperties({ 'zoom': 1.0, 'translation.x': 0.0, 'translation.y': 0.0 }, target) }
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
          <div style={{ fontSize: 12, opacity: 0.7 }}>PB: {health.patchbay ?? '…'} | MIDI: {health.midi ?? '…'}</div>
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
          {driveMode === 'midi' && (
            <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <input type="checkbox" checked={syncPE} onChange={(e) => setSyncPE(e.target.checked)} /> Sync PE
            </label>
          )}
          <button onClick={doReset}>Reset</button>
        </div>
      </header>
      <div ref={containerRef} style={{ height: '100%', display: 'grid', gridTemplateColumns: `${leftW}px ${GUTTER}px ${centerW}px ${GUTTER}px ${rightW}px` }}>
        {/* Left pane */}
        <div onDragOver={onDragOver} onDrop={onDropList('left')} style={{ overflowY: 'auto', borderRight: '1px solid #E6EAF2', padding: 8, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <FountainEditor />
          <div style={{ fontSize: 12, fontWeight: 600, marginTop: 6 }}>Left Pane</div>
          {leftItems.map(id => (
            <div key={id} draggable onDragStart={onDragStart(id, 'left')} style={{ fontSize: 12, padding: '4px 6px', cursor: 'grab' }}>{id}</div>
          ))}
        </div>
        {/* Left gutter */}
        <div onMouseDown={() => { if (dragState.current) dragState.current.which = 'left' }} style={{ cursor: 'col-resize', background: '#E6EAF2' }} />
        {/* Center (canvas only) */}
        <div onDragOver={onDragOver} onDrop={onDropCenter} style={{ position: 'relative' }}>
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
          {/* Flow graph overlay (nodes + noodles) */}
          <GraphOverlay scale={scale} tx={tx} ty={ty} />
          {/* Simple monitor */}
          <div style={{ position: 'absolute', right: 8, top: 8, background: 'rgba(255,255,255,0.9)', border: '1px solid #E6EAF2', borderRadius: 6, padding: '6px 8px', fontSize: 12, minWidth: 240 }}>
            <div style={{ fontWeight: 600, marginBottom: 4 }}>MIDI 2.0 Monitor</div>
            <div style={{ opacity: 0.7, marginBottom: 4 }}>mode: {driveMode.toUpperCase()} target: {target}</div>
            {log.slice(0, 5).map((l, i) => (
              <div key={i} style={{ whiteSpace: 'pre' }}>{l}</div>
            ))}
          </div>
        </div>
        {/* Right gutter */}
        <div onMouseDown={() => { if (dragState.current) dragState.current.which = 'right' }} style={{ cursor: 'col-resize', background: '#E6EAF2' }} />
        {/* Right pane */}
        <div onDragOver={onDragOver} onDrop={onDropList('right')} style={{ overflowY: 'auto', borderLeft: '1px solid #E6EAF2', padding: 8 }}>
          <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 6 }}>Right Pane</div>
          {rightItems.map(id => (
            <div key={id} draggable onDragStart={onDragStart(id, 'right')} style={{ fontSize: 12, padding: '4px 6px', cursor: 'grab' }}>{id}</div>
          ))}
        </div>
      </div>
    </div>
  )
}
