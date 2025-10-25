#!/usr/bin/env python3
"""
QC Prompt Kit Linter

Validates Design/QC_Prompt_Kit JSON schema and (optionally) cross-checks the
DSL header for canvas/autolayout parity.

Usage:
  python3 Scripts/design/qclint.py --json Design/QC_Prompt_Kit/qc_prompt.json \
                                   [--dsl Design/QC_Prompt_Kit/qc_prompt.dsl] \
                                   [--svg Design/QC_Prompt_Kit/qc_prompt.svg]

Exit codes:
  0 = OK
  1 = Lint errors (schema/consistency)
  2 = Usage error
"""
import argparse, json, re, sys, os

ALLOWED_SIDES = {"left", "right", "top", "bottom"}
ALLOWED_DIRS = {"in", "out"}
ALLOWED_ROUTING = {"qcBezier", "ortho"}
ALLOWED_LAYOUT = {"none", "flowLR", "flowTB"}

def err(msg):
    print(f"lint: ERROR: {msg}", file=sys.stderr)

def warn(msg):
    print(f"lint: WARN: {msg}", file=sys.stderr)

def parse_args():
    ap = argparse.ArgumentParser(description="QC Prompt Kit Linter")
    ap.add_argument("--json", required=True)
    ap.add_argument("--dsl")
    ap.add_argument("--svg")
    return ap.parse_args()

def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def parse_dsl_header(path):
    # Expect: canvas WxH theme=foo grid=N  and later: autolayout mode
    header = {}
    auto = None
    canvas_re = re.compile(r"^\s*canvas\s+(\d+)x(\d+)\s+(?:theme=(\w+))?\s*(?:grid=(\d+))?", re.I)
    autolayout_re = re.compile(r"^\s*autolayout\s+(\w+)", re.I)
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                m = canvas_re.match(line)
                if m:
                    header["width"] = int(m.group(1))
                    header["height"] = int(m.group(2))
                    if m.group(3): header["theme"] = m.group(3)
                    if m.group(4): header["grid"] = int(m.group(4))
                m2 = autolayout_re.match(line)
                if m2:
                    auto = m2.group(1)
    except FileNotFoundError:
        return None, None
    return header or None, auto

def lint(json_doc, dsl_header=None, dsl_auto=None, svg_path=None):
    ok = True
    # canvas
    canvas = json_doc.get("canvas")
    if not isinstance(canvas, dict):
        err("missing or invalid 'canvas'")
        ok = False
    else:
        for k in ("width","height"):
            if not isinstance(canvas.get(k), int) or canvas.get(k) <= 0:
                err(f"canvas.{k} must be positive int")
                ok = False
        if "theme" in canvas and not isinstance(canvas["theme"], str):
            err("canvas.theme must be string")
            ok = False
        if "grid" in canvas and (not isinstance(canvas["grid"], int) or canvas["grid"] <= 0):
            err("canvas.grid must be positive int")
            ok = False

    # nodes
    nodes = json_doc.get("nodes", [])
    if not isinstance(nodes, list) or not nodes:
        err("'nodes' must be a non-empty array")
        ok = False
    ids = set()
    port_map = {}  # Node.port -> (side, dir)
    for n in nodes:
        nid = n.get("id")
        if not isinstance(nid, str):
            err("node.id must be string")
            ok = False
            continue
        if nid in ids:
            err(f"duplicate node id: {nid}")
            ok = False
        ids.add(nid)
        for k in ("x","y","w","h"):
            if not isinstance(n.get(k), int):
                err(f"node {nid}: {k} must be int")
                ok = False
        ports = n.get("ports", [])
        if not isinstance(ports, list):
            err(f"node {nid}: ports must be array")
            ok = False
        seen_port_ids = set()
        for p in ports:
            pid = p.get("id")
            side = p.get("side")
            direc = p.get("dir")
            if not isinstance(pid, str):
                err(f"node {nid}: port.id must be string")
                ok = False
                continue
            if pid in seen_port_ids:
                err(f"node {nid}: duplicate port id '{pid}'")
                ok = False
            seen_port_ids.add(pid)
            if side not in ALLOWED_SIDES:
                err(f"node {nid}: port {pid} invalid side '{side}'")
                ok = False
            if direc not in ALLOWED_DIRS:
                err(f"node {nid}: port {pid} invalid dir '{direc}'")
                ok = False
            port_map[f"{nid}.{pid}"] = (side, direc)

    # edges
    edges = json_doc.get("edges", [])
    if not isinstance(edges, list):
        err("'edges' must be array")
        ok = False
    for e in edges:
        frm = e.get("from"); to = e.get("to")
        if frm not in port_map:
            err(f"edge.from references unknown port '{frm}'")
            ok = False
        if to not in port_map:
            err(f"edge.to references unknown port '{to}'")
            ok = False
        routing = e.get("routing", "qcBezier")
        if routing not in ALLOWED_ROUTING:
            err(f"edge routing '{routing}' invalid")
            ok = False
        if "width" in e and not isinstance(e["width"], (int, float)):
            err("edge.width must be number")
            ok = False
        if "glow" in e and not isinstance(e["glow"], bool):
            err("edge.glow must be boolean")
            ok = False

    # autolayout
    auto = json_doc.get("autolayout", "none")
    if auto not in ALLOWED_LAYOUT:
        err(f"autolayout '{auto}' invalid; expected one of {sorted(ALLOWED_LAYOUT)}")
        ok = False

    # notes
    notes = json_doc.get("notes", [])
    if notes is not None:
        if not isinstance(notes, list):
            err("notes must be array if present")
            ok = False
        else:
            for i, note in enumerate(notes):
                if not isinstance(note.get("text"), str):
                    err(f"notes[{i}].text must be string")
                    ok = False

    # DSL parity (header and autolayout)
    if dsl_header is not None:
        dc = dsl_header
        jc = canvas or {}
        for k in ("width","height"):
            if k in dc and k in jc and dc[k] != jc[k]:
                err(f"DSL canvas.{k}={dc[k]} != JSON canvas.{k}={jc[k]}")
                ok = False
        if "theme" in dc and "theme" in jc and dc["theme"] != jc["theme"]:
            warn(f"DSL theme '{dc['theme']}' != JSON theme '{jc['theme']}'")
        if "grid" in dc and "grid" in jc and dc["grid"] != jc["grid"]:
            warn(f"DSL grid {dc['grid']} != JSON grid {jc['grid']}")
    if dsl_auto is not None and auto != dsl_auto:
        warn(f"DSL autolayout '{dsl_auto}' != JSON '{auto}'")

    # SVG existence (optional)
    if svg_path:
        if not os.path.exists(svg_path):
            err(f"SVG not found: {svg_path}")
            ok = False

    return ok

def main():
    args = parse_args()
    try:
        doc = read_json(args.json)
    except Exception as e:
        err(f"failed to read JSON: {e}")
        return 2
    dsl_header = dsl_auto = None
    if args.dsl:
        dsl_header, dsl_auto = parse_dsl_header(args.dsl)
    ok = lint(doc, dsl_header, dsl_auto, args.svg)
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())

