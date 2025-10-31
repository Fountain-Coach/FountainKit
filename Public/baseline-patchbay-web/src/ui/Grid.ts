export interface GridParams { step: number; scale: number; tx: number; ty: number }

// Draw a crisp grid honoring zoom and translation, viewport-anchored left/top lines
export function drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number, p: GridParams) {
  const minor = p.step
  const majorEvery = 5
  const stepPx = minor * p.scale

  ctx.save()
  ctx.fillStyle = '#FAFBFD'
  ctx.fillRect(0, 0, w, h)

  // World→view mapping for a world x to view x: viewX = (x + tx) * scale
  const toViewX = (x: number) => (x + p.tx) * p.scale
  const toViewY = (y: number) => (y + p.ty) * p.scale

  // Find the first vertical grid line in view within [0, w)
  const startXWorld = Math.floor((-p.tx) / minor) * minor
  const startYWorld = Math.floor((-p.ty) / minor) * minor

  // Minor lines
  ctx.strokeStyle = '#ECEEF3'
  ctx.lineWidth = 1

  for (let x = startXWorld; x < (w / p.scale - p.tx) + minor; x += minor) {
    const vx = Math.round(toViewX(x)) + 0.5 // crisp
    ctx.beginPath()
    ctx.moveTo(vx, 0)
    ctx.lineTo(vx, h)
    ctx.stroke()
  }
  for (let y = startYWorld; y < (h / p.scale - p.ty) + minor; y += minor) {
    const vy = Math.round(toViewY(y)) + 0.5
    ctx.beginPath()
    ctx.moveTo(0, vy)
    ctx.lineTo(w, vy)
    ctx.stroke()
  }

  // Major lines
  ctx.strokeStyle = '#D1D6E0'
  for (let x = startXWorld; x < (w / p.scale - p.tx) + minor * majorEvery; x += minor * majorEvery) {
    const vx = Math.round(toViewX(x)) + 0.5
    ctx.beginPath()
    ctx.moveTo(vx, 0)
    ctx.lineTo(vx, h)
    ctx.stroke()
  }
  for (let y = startYWorld; y < (h / p.scale - p.ty) + minor * majorEvery; y += minor * majorEvery) {
    const vy = Math.round(toViewY(y)) + 0.5
    ctx.beginPath()
    ctx.moveTo(0, vy)
    ctx.lineTo(w, vy)
    ctx.stroke()
  }

  // Doc axes (x=0/y=0)
  ctx.strokeStyle = '#BF3434'
  {
    const vx = Math.round(toViewX(0)) + 0.5
    ctx.beginPath(); ctx.moveTo(vx, 0); ctx.lineTo(vx, h); ctx.stroke()
  }
  {
    const vy = Math.round(toViewY(0)) + 0.5
    ctx.beginPath(); ctx.moveTo(0, vy); ctx.lineTo(w, vy); ctx.stroke()
  }

  ctx.restore()
}

