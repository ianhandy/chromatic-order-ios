"""Grade the procedural difficulty ladder the same way as the campaign:
how much of each board can be deduced, and how fine the eye-only calls are.
"""
import json, statistics, sys
sys.path.insert(0, "/Users/ianhandy/Programming/repos/chromatic-order-ios/tools/campaign")
from oklch import OKLCh, dist

data = json.load(open("/tmp/kroma-ladder-export.json"))
levels = data["levels"] if isinstance(data, dict) else data
print("export keys:", list(data.keys()) if isinstance(data, dict) else "list")

def analyse(entry):
    cells, locked, runs = {}, set(), []
    for g in entry["doc"]["gradients"]:
        run = []
        for c in g["cells"]:
            key = (c["r"], c["c"])
            cells[key] = OKLCh(c["L"], c["C"], c["h"])
            if c.get("locked"): locked.add(key)
            run.append(key)
        runs.append(run)
    known = set(locked)
    changed = True
    while changed:
        changed = False
        for run in runs:
            if sum(1 for k in run if k in known) >= 2:
                for k in run:
                    if k not in known:
                        known.add(k); changed = True
    free = [k for k in cells if k not in locked]
    bank = [cells[k] for k in free]
    margins = {}
    for i, k in enumerate(free):
        rivals = [dist(cells[k], bank[j]) for j in range(len(bank)) if j != i]
        margins[k] = min(rivals) if rivals else float("inf")
    by_eye = [k for k in free if k not in known]
    eye_worst = min((margins[k] for k in by_eye), default=None)
    return dict(bank=len(free), by_eye=len(by_eye), eye_worst=eye_worst,
                full_deduce=len(by_eye) == 0,
                board_min=min(margins.values()) if margins else None)

by_level = {}
for entry in levels:
    lv = entry.get("level") or int(entry["chapter"].split()[-1])
    by_level.setdefault(lv, []).append(analyse(entry))

print(f"\n{'lv':>3} {'n':>3} {'bank':>5} {'byEye':>6} {'eyeWorst':>9} {'boardMin':>9} {'fullyDeduced':>13}")
for lv in sorted(by_level):
    rows = by_level[lv]
    eye_worsts = [r["eye_worst"] for r in rows if r["eye_worst"] is not None]
    print(f"{lv:3d} {len(rows):3d} {statistics.mean(r['bank'] for r in rows):5.1f} "
          f"{statistics.mean(r['by_eye'] for r in rows):6.1f} "
          f"{(statistics.mean(eye_worsts) if eye_worsts else float('nan')):9.1f} "
          f"{statistics.mean(r['board_min'] for r in rows if r['board_min']):9.1f} "
          f"{100*sum(1 for r in rows if r['full_deduce'])/len(rows):12.0f}%")
