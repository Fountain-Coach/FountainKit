canvas 900x560 theme=dark grid=24

node Source at (100,120) size (200,110) {
  port in  left  name:in   type:data
  port out right name:out  type:data
}

node Filter at (520,280) size (200,110) {
  port in  left  name:in   type:data
  port out right name:out  type:data
}

edge Source.out -> Filter.in style qcBezier width=3.5 glow
note "drag to connect…" at (620,230)

autolayout none
