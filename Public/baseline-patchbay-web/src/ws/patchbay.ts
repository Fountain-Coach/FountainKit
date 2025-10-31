export interface Point { x: number; y: number }
export interface CanvasState { gridStep?: number; transform: { scale: number; translation: Point } }

const base = (path: string) => `/api/patchbay${path}`

export async function getCanvas(): Promise<CanvasState> {
  const r = await fetch(base('/canvas'))
  if (!r.ok) throw new Error(`GET /canvas failed: ${r.status}`)
  return await r.json()
}

export async function zoomSet(body: { scale: number; anchorView?: Point }) {
  const r = await fetch(base('/canvas/zoom'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
  if (!r.ok) throw new Error(`POST /canvas/zoom failed: ${r.status}`)
}

export async function panBy(body: { dx: number; dy: number }) {
  const r = await fetch(base('/canvas/pan'), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
  if (!r.ok) throw new Error(`POST /canvas/pan failed: ${r.status}`)
}

export function resetTransform(currentScale: number, tx: number, ty: number): { dx: number; dy: number; nextScale: number } {
  const dx = -tx
  const dy = -ty
  return { dx, dy, nextScale: 1.0 }
}

