#!/usr/bin/env python3
"""
QC Prompt Kit JSON → SVG preview renderer with numbered grid and axes.

Usage:
  python3 Scripts/design/qcrender.py --json Design/QC_Prompt_Kit/qc_prompt.json \
                                     --out Design/QC_Prompt_Kit/qc_preview.svg

Notes:
- Ports are placed evenly along each side in ID order.
- Edge routing uses horizontal-tangent cubic Béziers (qcBezier) by default.
"""
import argparse, json, os, sys

def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", required=True)
    ap.add_argument("--out", required=True)
    return ap.parse_args()

def load_doc(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def theme_colors(theme: str):
    light = {
        'bg': '#ffffff', 'grid': '#eaeff3', 'grid5': '#dae2e7', 'axis': '#90a4ae',
        'text': '#263238', 'node': '#f4f6f8', 'nodeStroke': '#cfd8dc',
        'edge': '#00B3A4', 'edgeGlow': '#00B3A422', 'title': '#2F74FF'
    }
    dark = {
        'bg': '#0e1116', 'grid': '#1c222b', 'grid5': '#2a333f', 'axis': '#607d8b',
        'text': '#eceff1', 'node': '#1a212b', 'nodeStroke': '#34414d',
        'edge': '#00B3A4', 'edgeGlow': '#00B3A455', 'title': '#64b5f6'
    }
    return dark if (theme or '').lower() == 'dark' else light

def esc(s: str) -> str:
    return (s or '').replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')

def layout_ports(node):
    # Return dict side -> list of (portId, (x,y)) evenly spaced
    sides = {'left': [], 'right': [], 'top': [], 'bottom': []}
    for p in sorted(node.get('ports', []), key=lambda p: p.get('id','')):
        side = p.get('side','left')
        if side in sides:
            sides[side].append(p.get('id'))
    pos = {}
    x,y,w,h = node['x'], node['y'], node['w'], node['h']
    for side, plist in sides.items():
        n = len(plist)
        if n == 0: continue
        for i,pid in enumerate(plist):
            if side == 'left':
                px = x; py = y + int((i+1)*(h/(n+1)))
            elif side == 'right':
                px = x + w; py = y + int((i+1)*(h/(n+1)))
            elif side == 'top':
                px = x + int((i+1)*(w/(n+1))); py = y
            else: # bottom
                px = x + int((i+1)*(w/(n+1))); py = y + h
            pos[(side, pid)] = (px, py)
    return pos

def bezier_ctrl(from_side, x1,y1, x2,y2, radius=80):
    # Horizontal tangents near nodes
    if from_side == 'right':
        c1x, c1y = x1 + radius, y1
        c2x, c2y = x2 - radius, y2
    elif from_side == 'left':
        c1x, c1y = x1 - radius, y1
        c2x, c2y = x2 + radius, y2
    elif from_side == 'top':
        c1x, c1y = x1, y1 - radius
        c2x, c2y = x2, y2 + radius
    else: # bottom
        c1x, c1y = x1, y1 + radius
        c2x, c2y = x2, y2 - radius
    return c1x,c1y,c2x,c2y

def render(doc, out_path):
    canvas = doc.get('canvas', {})
    W = int(canvas.get('width', 900)); H = int(canvas.get('height', 560))
    grid = int(canvas.get('grid', 24))
    theme = canvas.get('theme', 'light')
    C = theme_colors(theme)

    nodes = doc.get('nodes', [])
    # Build node/port index
    node_by_id = {n['id']: n for n in nodes}
    port_pos = {}
    for n in nodes:
        for k,v in layout_ports(n).items():
            side, pid = k
            port_pos[(n['id'], pid)] = (side, v)

    # Begin SVG
    out = []
    a = out.append
    a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
    a(f'<rect width="{W}" height="{H}" fill="{C["bg"]}"/>')

    # Grid with numbers
    for x in range(0, W+1, grid):
        col = C['grid5'] if (x//grid) % 5 == 0 else C['grid']
        a(f'<line x1="{x}" y1="0" x2="{x}" y2="{H}" stroke="{col}" stroke-width="1"/>')
        a(f'<text x="{x+2}" y="14" font-family="sans-serif" font-size="10" fill="{C["axis"]}">{x}</text>')
    for y in range(0, H+1, grid):
        col = C['grid5'] if (y//grid) % 5 == 0 else C['grid']
        a(f'<line x1="0" y1="{y}" x2="{W}" y2="{y}" stroke="{col}" stroke-width="1"/>')
        a(f'<text x="2" y="{y-2}" font-family="sans-serif" font-size="10" fill="{C["axis"]}">{y}</text>')

    # Nodes
    for n in nodes:
        x,y,w,h = n['x'], n['y'], n['w'], n['h']
        title = esc(n.get('title') or n.get('id'))
        a(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" ry="8" fill="{C["node"]}" stroke="{C["nodeStroke"]}"/>')
        a(f'<text x="{x+w/2}" y="{y+18}" text-anchor="middle" font-family="sans-serif" font-size="14" fill="{C["title"]}">{title}</text>')
        # Ports
        per_side = {'left': [], 'right': [], 'top': [], 'bottom': []}
        for p in sorted(n.get('ports', []), key=lambda p: p.get('id','')):
            per_side[p.get('side','left')].append(p)
        for side, plist in per_side.items():
            nn = len(plist)
            for i,p in enumerate(plist):
                pid = p.get('id','')
                sx, sy = port_pos[(n['id'], pid)][1]
                a(f'<circle cx="{sx}" cy="{sy}" r="4" fill="{C["nodeStroke"]}"/>')
                # label
                dx = -8 if side == 'left' else 8
                anchor = 'end' if side == 'left' else 'start'
                a(f'<text x="{sx+dx}" y="{sy+4}" font-family="sans-serif" font-size="10" fill="{C["text"]}" text-anchor="{anchor}">{esc(pid)}</text>')

    # Edges
    for e in doc.get('edges', []):
        frm = e.get('from',''); to = e.get('to','')
        if '.' not in frm or '.' not in to: 
            continue
        fn, fp = frm.split('.',1); tn, tp = to.split('.',1)
        if (fn, fp) not in port_pos or (tn, tp) not in port_pos: 
            continue
        fside,(x1,y1) = port_pos[(fn, fp)]
        tside,(x2,y2) = port_pos[(tn, tp)]
        c1x,c1y,c2x,c2y = bezier_ctrl(fside, x1,y1, x2,y2)
        width = float(e.get('width', 2.0))
        if e.get('glow', False):
            a(f'<path d="M{x1},{y1} C{c1x},{c1y} {c2x},{c2y} {x2},{y2}" fill="none" stroke="{C["edgeGlow"]}" stroke-width="{width*2}"/>')
        a(f'<path d="M{x1},{y1} C{c1x},{c1y} {c2x},{c2y} {x2},{y2}" fill="none" stroke="{C["edge"]}" stroke-width="{width}"/>')

    a('</svg>')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))

def main():
    args = parse_args()
    doc = load_doc(args.json)
    render(doc, args.out)

if __name__ == '__main__':
    sys.exit(main())

