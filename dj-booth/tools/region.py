"""Print a golden's drawn items inside a region (panel coordinates), compactly.
usage: python tools/region.py <state> x0 y0 x1 y1 [--all]"""
import json, sys, os
state, x0, y0, x1, y1 = sys.argv[1], *map(float, sys.argv[2:6])
show_all = "--all" in sys.argv
p = os.path.join(os.path.dirname(__file__), "..", "tests", "golden", f"golden_{state}.json")
d = json.load(open(p, encoding="utf-8"))
for e in d["items"]:
    x, y, w, h = e["r"]
    if x >= x0 and y >= y0 and x + w <= x1 and y + h <= y1:
        drawn = e.get("bg") or e.get("t") or e.get("im") or e.get("st")
        if not drawn and not show_all:
            continue
        parts = [f"{e['k'][:5]:5} {x:g},{y:g} {w:g}x{h:g}"]
        if e.get("bg"): parts.append("bg=" + e["bg"] + (f"/{e['bt']}" if e.get("bt") else ""))
        if e.get("cr"): parts.append(f"r={e['cr']:g}")
        if e.get("st"): parts.append("st=" + str(e["st"]))
        if e.get("gr"): parts.append("gr=" + str(e["gr"][0]) + (f" rot={e['gr'][2]}" if e['gr'][2] else ""))
        if e.get("rot"): parts.append(f"rot={e['rot']}")
        t = e.get("t")
        if t: parts.append(f"'{t[0]}' {t[2]} {t[4]:g} #{t[5]}" + (f" tt={t[6]}" if t[6] else "") + f" {t[7][0]}{t[8][0]} tb={t[9]:g}x{t[10]:g}")
        im = e.get("im")
        if im: parts.append("img=" + im[0].split("/")[-1] + f" #{im[1]}")
        print("  ".join(parts))
