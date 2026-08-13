"""Which cells can be reasoned out, and which have to be matched by eye.

A player has two channels. One is deduction: a run with two known cells fixes
its whole ramp (step = the gap between them divided by their distance apart),
and a known cell shared with another run hands that run a second anchor, so
knowledge spreads exactly like a crossword. The other is discrimination:
looking at a swatch and judging which cell it belongs to.

Deduction is free. Discrimination costs, and it fails when the correct swatch
is barely closer than the next best one. So the number that decides whether a
level is fair is not its overall colour separation, it is the separation on the
cells that deduction cannot reach.

This module computes the deduction closure and reports margins split by class,
which is what the difficulty tuning in build.py aims at.
"""

from __future__ import annotations

import json
import statistics
from pathlib import Path

from oklch import OKLCh, dist

CAMPAIGN = Path(__file__).resolve().parents[2] / "ChromaticOrder" / "Resources" / "campaign.json"


def load_level(entry: dict):
    """Board cells, gradients as ordered cell lists, and the given cells."""
    cells: dict[tuple[int, int], OKLCh] = {}
    locked: set[tuple[int, int]] = set()
    gradients: list[list[tuple[int, int]]] = []
    for grad in entry["doc"]["gradients"]:
        run = []
        for cell in grad["cells"]:
            key = (cell["r"], cell["c"])
            cells[key] = OKLCh(cell["L"], cell["C"], cell["h"])
            if cell.get("locked"):
                locked.add(key)
            run.append(key)
        gradients.append(run)
    return cells, gradients, locked


def deduction_closure(gradients, known: set) -> set:
    """Cells a player can compute rather than recognise.

    Repeat until nothing new: any run holding two known cells has its whole
    ramp determined, so every other cell on that run becomes known, and that
    knowledge crosses into other runs through shared cells.
    """
    known = set(known)
    changed = True
    while changed:
        changed = False
        for run in gradients:
            if sum(1 for cell in run if cell in known) >= 2:
                for cell in run:
                    if cell not in known:
                        known.add(cell)
                        changed = True
    return known


def sorting_check(cells, gradients, locked) -> dict:
    """The three things a player needs in order to lay a board down.

    They do not match swatches against empty cells, because an empty cell shows
    nothing to match. They sort:

      partition  group the swatches by which run they belong to, which works
                 while a swatch's nearest neighbour is in its own run,
      order      arrange each group along its ramp, which works while
                 consecutive steps beat the eye's noise,
      orient     decide which way round the run goes, which needs a given cell
                 on the run or a crossing that inherits one.

    Any of the three failing is a real defect. A tight colour gap on a cell that
    deduction pins exactly is not.
    """
    run_of = {}
    for gi, run in enumerate(gradients):
        for cell in run:
            run_of.setdefault(cell, gi)

    free = [cell for cell in cells if cell not in locked]
    # Partition: for each empty cell's colour, is the closest other colour on
    # the board in the same run? If not, that swatch is ambiguous to group.
    confusable = 0
    for cell in free:
        others = [(dist(cells[cell], cells[other]), other)
                  for other in cells if other != cell]
        if not others:
            continue
        _, nearest = min(others)
        if run_of.get(nearest) != run_of.get(cell):
            confusable += 1

    # Order: the smallest consecutive step on any run.
    steps = []
    for run in gradients:
        for i in range(len(run) - 1):
            steps.append(dist(cells[run[i]], cells[run[i + 1]]))
    # Orient: runs with no given cell and no crossing, spread through crossings.
    oriented = {gi for gi, run in enumerate(gradients)
                if any(cell in locked for cell in run)}
    changed = True
    while changed:
        changed = False
        for gi, run in enumerate(gradients):
            if gi in oriented:
                continue
            for gj, other in enumerate(gradients):
                if gj != gi and gj in oriented and set(run) & set(other):
                    oriented.add(gi)
                    changed = True
                    break
    return {
        "confusable": confusable,
        "min_step": min(steps) if steps else None,
        "floating": len(gradients) - len(oriented),
    }


def analyse(entry: dict) -> dict:
    cells, gradients, locked = load_level(entry)
    free = [cell for cell in cells if cell not in locked]
    bank = [cells[cell] for cell in free]

    # Nearest rival swatch for each empty cell: how much closer the right
    # answer is than the next best one.
    margin = {}
    for i, cell in enumerate(free):
        truth = cells[cell]
        rivals = [dist(truth, bank[j]) for j in range(len(bank)) if j != i]
        margin[cell] = min(rivals) if rivals else float("inf")

    reachable = deduction_closure(gradients, locked)
    forced = [cell for cell in free if cell in reachable]
    matched = [cell for cell in free if cell not in reachable]

    def stats(group):
        values = [margin[cell] for cell in group if margin[cell] != float("inf")]
        if not values:
            return None, None
        return min(values), statistics.median(values)

    forced_min, forced_med = stats(forced)
    matched_min, matched_med = stats(matched)
    return {
        "index": entry["index"],
        "name": entry["name"],
        "chapter": entry["chapter"],
        "bank": len(free),
        "forced": len(forced),
        "matched": len(matched),
        "forced_min": forced_min,
        "matched_min": matched_min,
        "matched_med": matched_med,
    }


def main() -> int:
    campaign = json.loads(CAMPAIGN.read_text())
    rows = [analyse(entry) for entry in campaign["levels"]]

    print(f"{'lv':>3} {'name':12} {'bank':>4} {'deduced':>7} {'by eye':>6} "
          f"{'eye worst':>9} {'eye median':>10}  verdict")
    unfair = []
    for row in rows:
        eye_worst = row["matched_min"]
        eye_text = f"{eye_worst:9.1f}" if eye_worst is not None else "        -"
        med_text = f"{row['matched_med']:10.1f}" if row["matched_med"] is not None else "         -"
        if eye_worst is None:
            verdict = "all deducible"
        elif eye_worst < 5:
            verdict = "UNFAIR: eye-only call under 5"
            unfair.append(row)
        elif eye_worst < 7:
            verdict = "tight"
        else:
            verdict = "fair"
        print(f"{row['index']:3d} {row['name']:12} {row['bank']:4d} {row['forced']:7d} "
              f"{row['matched']:6d} {eye_text} {med_text}  {verdict}")

    print(f"\nlevels where deduction reaches every cell: "
          f"{sum(1 for r in rows if r['matched'] == 0)}/{len(rows)}")
    print(f"levels needing an eye-only call under delta-E 5: {len(unfair)}")
    if unfair:
        print("  " + ", ".join(f"{r['index']} {r['name']}" for r in unfair))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
