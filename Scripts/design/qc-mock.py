#!/usr/bin/env python3
"""
QC Mock — a lightweight, keyboard-driven mocking tool (curses) on a numbered grid.

Quartz Composer–inspired: place nodes, add ports, connect edges, and save.
Produces qc_prompt.json and qc_prompt.dsl that the LLM can read and translate.

Keys:
  Arrows / h j k l  Move cursor
  n                 New node at cursor (fixed size, prompt for id/title)
  p                 Add port to selected node (choose side, dir, id)
  TAB               Cycle selected node under cursor
  e                 Connect edge: pick from-port then to-port
  s                 Save (JSON + DSL) into the kit directory
  g                 Toggle grid labels
  q                 Quit

Usage:
  python3 Scripts/design/qc-mock.py --kit Design/QC_Prompt_Kit

Notes:
  - This is a minimal mocking tool for quick ideation and LLM-ready specs.
  - Node size is fixed for simplicity; adjust later in JSON/DSL if needed.
  - Ports are rendered by side initials; edges are indicative lines only.
"""
import curses, json, os, sys, argparse

DEFAULT_CANVAS = {"width": 900, "height": 560, "theme": "light", "grid": 24}
NODE_W, NODE_H = 18, 7  # grid cells (visual only)

def load_kit(kit):
    json_path = os.path.join(kit, "qc_prompt.json")
    if os.path.exists(json_path):
        with open(json_path, 'r', encoding='utf-8') as f:
            doc = json.load(f)
    else:
        doc = {"canvas": DEFAULT_CANVAS.copy(), "nodes": [], "edges": [], "notes": [], "autolayout": "none"}
    return doc

def save_kit(kit, doc):
    json_path = os.path.join(kit, "qc_prompt.json")
    dsl_path = os.path.join(kit, "qc_prompt.dsl")
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(doc, f, indent=2)
    with open(dsl_path, 'w', encoding='utf-8') as f:
        c = doc.get('canvas', {})
        theme = f" theme={c.get('theme','light')}" if 'theme' in c else ""
        grid = f" grid={c.get('grid',24)}" if 'grid' in c else ""
        f.write(f"canvas {c.get('width',900)}x{c.get('height',560)}{theme}{grid}\n\n")
        for n in doc.get('nodes', []):
            f.write(f"node {n['id']} at ({n['x']},{n['y']}) size ({n['w']},{n['h']}) {{\n")
            for p in n.get('ports', []):
                f.write(f"  port {p['dir']} {p['side']} name:{p['id']} type:{p.get('type','data')}\n")
            f.write("}\n\n")
        for e in doc.get('edges', []):
            style = f" style {e.get('routing','qcBezier')}"
            width = f" width={e.get('width',2.0)}" if 'width' in e else ""
            glow = " glow" if e.get('glow') else ""
            f.write(f"edge {e['from']} -> {e['to']}{style}{width}{glow}\n")
        f.write(f"\nautolayout {doc.get('autolayout','none')}\n")

def grid_dims(doc):
    c = doc.get('canvas', DEFAULT_CANVAS)
    return int(c.get('width',900)), int(c.get('height',560)), int(c.get('grid',24))

def snap(x, g):
    return int(round(x / g) * g)

def draw(stdscr, doc, cx, cy, show_labels, selected_idx):
    stdscr.clear()
    H, W = stdscr.getmaxyx()
    Wp, Hp, G = grid_dims(doc)
    # scale canvas to terminal cells: 1 grid unit → 2 chars, 1 line
    sx = max(1, min(2, (W-2)//max(1,(Wp//G+2))))
    sy = 1
    # draw grid
    cols = Wp // G + 1
    rows = Hp // G + 1
    for i in range(cols):
        x = 1 + i*sx
        for y in range(1, min(H-1, rows*sy)+1):
            stdscr.addch(y, x, '|')
        if show_labels and i % 5 == 0:
            label = str(i*G)
            stdscr.addstr(0, max(1, x-len(label)//2), label)
    for j in range(rows):
        y = 1 + j*sy
        stdscr.hline(y, 1, '-', min(W-2, cols*sx))
        if show_labels and j % 5 == 0:
            label = str(j*G)
            stdscr.addstr(y, 0, label)
    # draw nodes
    for idx, n in enumerate(doc.get('nodes', [])):
        x = int(n['x']//G)*sx + 1
        y = int(n['y']//G)*sy + 1
        w = max(4, int(n['w']//G)*sx)
        h = max(2, int(n['h']//G)*sy)
        ch = '#' if idx == selected_idx else '+'
        for yy in range(y, min(H-1, y+h)):
            if yy == y or yy == y+h-1:
                stdscr.hline(yy, x, ch, min(W-2, w))
            else:
                if x < W-1:
                    stdscr.addch(yy, x, ch)
                if x+w-1 < W-1:
                    stdscr.addch(yy, min(W-2, x+w-1), ch)
        label = n['id'][:max(1,min(w-2,20))]
        if y+1 < H and x+1 < W:
            stdscr.addstr(y+1, x+1, label)
    # cursor
    stdscr.addch(max(1,min(H-1, 1 + (cy//G)*sy)), max(1,min(W-2, 1 + (cx//G)*sx)), '*')
    # footer
    help1 = "Arrows/hjkl move • n new node • p add port • e connect • TAB cycle • s save • g grid • q quit"
    stdscr.addstr(H-1, 1, help1[:W-2])
    stdscr.refresh()

def prompt(stdscr, question):
    curses.echo()
    stdscr.addstr(0, 2, ' ' * (curses.COLS-4))
    stdscr.addstr(0, 2, question)
    stdscr.refresh()
    s = stdscr.getstr(0, 2 + len(question), 60).decode('utf-8').strip()
    curses.noecho()
    return s

def pick_node(doc, stdscr, prompt_text="Select node id:"):
    ids = [n['id'] for n in doc.get('nodes', [])]
    if not ids:
        return None
    stdscr.addstr(0,2, ' '*(curses.COLS-4))
    stdscr.addstr(0,2, prompt_text + ' ' + ','.join(ids))
    stdscr.refresh()
    curses.echo(); s = stdscr.getstr(0, 2+len(prompt_text)+1, 40).decode('utf-8').strip(); curses.noecho()
    return s if s in ids else None

def pick_port(node, stdscr, prompt_text="Select port id:"):
    ports = [p['id'] for p in node.get('ports', [])]
    if not ports:
        return None
    stdscr.addstr(0,2, ' '*(curses.COLS-4))
    stdscr.addstr(0,2, prompt_text + ' ' + ','.join(ports))
    stdscr.refresh()
    curses.echo(); s = stdscr.getstr(0, 2+len(prompt_text)+1, 40).decode('utf-8').strip(); curses.noecho()
    return s if s in ports else None

def run(stdscr, kit):
    curses.curs_set(0)
    doc = load_kit(kit)
    Wp, Hp, G = grid_dims(doc)
    cx, cy = G*2, G*2
    show_labels = True
    selected_idx = -1
    while True:
        draw(stdscr, doc, cx, cy, show_labels, selected_idx)
        ch = stdscr.getch()
        if ch in (ord('q'), 27):
            break
        elif ch in (curses.KEY_RIGHT, ord('l')):
            cx = min(Wp-G, cx+G)
        elif ch in (curses.KEY_LEFT, ord('h')):
            cx = max(0, cx-G)
        elif ch in (curses.KEY_UP, ord('k')):
            cy = max(0, cy-G)
        elif ch in (curses.KEY_DOWN, ord('j')):
            cy = min(Hp-G, cy+G)
        elif ch == ord('g'):
            show_labels = not show_labels
        elif ch == ord('\t'):
            if doc.get('nodes'):
                selected_idx = (selected_idx + 1) % len(doc['nodes'])
        elif ch == ord('n'):
            nid = prompt(stdscr, "node id: ")
            if not nid:
                continue
            title = prompt(stdscr, "title (optional): ")
            node = {
                "id": nid,
                "title": title or nid,
                "x": snap(cx, G), "y": snap(cy, G),
                "w": G*NODE_W//2, "h": G*NODE_H//2,
                "ports": []
            }
            doc.setdefault('nodes', []).append(node)
            selected_idx = len(doc['nodes'])-1
        elif ch == ord('p'):
            if selected_idx < 0 or selected_idx >= len(doc.get('nodes', [])):
                continue
            node = doc['nodes'][selected_idx]
            pid = prompt(stdscr, "port id: ")
            side = prompt(stdscr, "side (left/right/top/bottom): ")
            direc = prompt(stdscr, "dir (in/out): ")
            ptype = prompt(stdscr, "type (data/event/audio/midi): ") or 'data'
            if side not in ("left","right","top","bottom") or direc not in ("in","out") or not pid:
                continue
            node.setdefault('ports', []).append({"id": pid, "side": side, "dir": direc, "type": ptype})
        elif ch == ord('e'):
            src_id = pick_node(doc, stdscr, "from node:")
            if not src_id: 
                continue
            src = next(n for n in doc['nodes'] if n['id']==src_id)
            src_port = pick_port(src, stdscr, "from port:")
            if not src_port:
                continue
            dst_id = pick_node(doc, stdscr, "to node:")
            if not dst_id:
                continue
            dst = next(n for n in doc['nodes'] if n['id']==dst_id)
            dst_port = pick_port(dst, stdscr, "to port:")
            if not dst_port:
                continue
            doc.setdefault('edges', []).append({"from": f"{src_id}.{src_port}", "to": f"{dst_id}.{dst_port}", "routing": "qcBezier", "width": 2.0})
        elif ch == ord('s'):
            save_kit(kit, doc)
            stdscr.addstr(0,2, f"Saved to {kit}/qc_prompt.json + qc_prompt.dsl")
            stdscr.refresh(); curses.napms(600)

def main():
    ap = argparse.ArgumentParser(description="QC Mock (curses)")
    ap.add_argument("--kit", default="Design/QC_Prompt_Kit")
    args = ap.parse_args()
    os.makedirs(args.kit, exist_ok=True)
    curses.wrapper(run, args.kit)

if __name__ == '__main__':
    sys.exit(main())

