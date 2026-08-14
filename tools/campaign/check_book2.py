"""Independent structural check on book two's authored chapters.

Written separately from the authoring pass on purpose. Twice in this project a
second implementation of a rule disagreed with the first and the disagreement
was the bug (the lazy-generator step check, and the reversal test that judged a
run in isolation), so the shapes get checked by code that did not draw them.

This only looks at structure. Colour fairness is build.py's job, and it is
enforced there: `choose_locks` hands out extra given cells until every run can
be oriented and no alternative arrangement survives a player's checks, and it
fails the build outright when it cannot. What this catches is the cheaper class
of mistake, the kind that would otherwise show up as a mysteriously large bank
or a level that will not build at all.

    python3 check_book2.py
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import art  # noqa: E402
import shapes as book_one  # noqa: E402

# (module, chapter title, first level, last level, max width, max height,
#  gradient range, cell range)
CHAPTERS = [
    ("book2.ch08_workshop", "Workshop", 101, 120, 9, 7, (6, 8), (20, 32)),
    ("book2.ch09_orchestra", "Orchestra", 121, 140, 11, 7, (7, 9), (24, 36)),
    ("book2.ch10_circuitry", "Circuitry", 141, 160, 11, 8, (7, 10), (26, 40)),
    ("book2.ch11_interiors", "Interiors", 161, 180, 11, 9, (8, 10), (28, 42)),
    ("book2.ch12_grand_works", "Grand Works", 181, 200, 11, 9, (9, 12), (32, 50)),
]


def crossing_positions(shape, gi: int) -> set[int]:
    """Where this run meets another, as 0-indexed offsets along the run."""
    grad = shape.gradients[gi]
    out = set()
    for pos, cell in enumerate(grad.cells):
        for gj, other in enumerate(shape.gradients):
            if gj != gi and cell in other.cells:
                out.add(pos)
                break
    return out


def reversible(shape, gi: int) -> bool:
    """Can this run be laid down backwards without anything on screen moving?

    Reversal maps offset i to n-1-i. If the crossings land back on crossings,
    the shared cells cannot tell the player which way round the run goes, and
    the level has to spend given cells to say so instead.

    A run with no crossings at all is trivially reversible under this test, but
    that is not the same defect: such a run is anchored by a given cell rather
    than by a neighbour, which build.py arranges. Report it separately.
    """
    n = len(shape.gradients[gi].cells)
    P = crossing_positions(shape, gi)
    return bool(P) and {n - 1 - i for i in P} == P


def component_span(shape) -> tuple[int, int, int]:
    """The reach of the largest connected cluster of crossings.

    build.py paints an over-determined cluster as one field that is linear in
    OKLab, so the travel it needs is span x step size. At the 5.4 delta-E step
    floor a 10 column span asks for about 54 delta-E in one direction and 38 in
    the other, and that rectangle does not fit in the usable sRGB volume.

    What binds is the AREA the cluster covers, not either span alone. The field
    has to travel on both axes at once, so the parallelogram it sweeps in OKLab
    grows as row span x column span, and it is that parallelogram which has to
    fit inside the usable volume. One long axis is affordable; two is not.

    Fitted against every book two draft built end to end (40 shapes, 3 outright
    failures and 3 that only built by abandoning the between-run separation
    rule), splitting on area separates them exactly:

        6r x 10c = 60   builds, separation held at 0.70 to 0.74
        8r x  8c = 64   builds, at the edge (closest pair 3.99 delta-E)
        7r x 10c = 70   Foundry, Smelter, Ironworks: no palette exists.
                        Gantry and Powerhouse: separation collapsed to ~0
        8r x  9c = 72   Spire: separation 0, closest pair 3.91 delta-E

    A span limit on each axis separately does not work, and my first attempt at
    one flagged Shipyard, Breakwater and Water Tower, all of which build
    comfortably. Note also that this is about the cluster and not the board: an
    11 wide shape whose crossings split it into three clusters is fine.

    Returns (gradients in the biggest cluster, row span, column span).
    """
    graph = art.crossing_graph(shape)
    seen: set[int] = set()
    comps: list[set[int]] = []
    for i in range(len(shape.gradients)):
        if i in seen:
            continue
        stack, comp = [i], set()
        while stack:
            x = stack.pop()
            if x in comp:
                continue
            comp.add(x)
            seen.add(x)
            stack.extend(j for j, _, _ in graph[x])
        comps.append(comp)
    big = max(comps, key=len)
    cells = [cell for gi in big for cell in shape.gradients[gi].cells]
    rows = [r for r, _ in cells]
    cols = [c for _, c in cells]
    return len(big), max(rows) - min(rows), max(cols) - min(cols)


# Largest cluster area that measured as buildable. 64 built (at the edge), 70
# did not.
SPAN_AREA_LIMIT = 64


def main() -> int:
    # `shapes.ALL` includes Book 2 once the chapters are wired into the real
    # build. Only seed this set from the first hundred, otherwise every Book 2
    # entry reports itself as a duplicate.
    used = {name.lower() for name, _, _ in book_one.ALL[:100]}
    problems: list[str] = []
    total_cells = 0
    rows = []

    for mod_name, title, first, last, max_w, max_h, grads, cells in CHAPTERS:
        try:
            mod = importlib.import_module(mod_name)
        except ModuleNotFoundError:
            print(f"  {title:12} not written yet")
            continue

        entries = mod.SHAPES
        want = last - first + 1
        if len(entries) != want:
            problems.append(f"{title}: {len(entries)} shapes, expected {want}")

        for offset, (name, drawing, tip) in enumerate(entries):
            level = first + offset
            where = f"{level} {name}"
            try:
                shape = art.parse(drawing, name)
            except Exception as exc:  # noqa: BLE001
                problems.append(f"{where}: does not parse: {exc}")
                continue

            n_cells = len(shape.all_cells)
            n_grads = len(shape.gradients)
            total_cells += n_cells

            if name.lower() in used:
                problems.append(f"{where}: name already used")
            used.add(name.lower())

            if shape.grid_w > max_w or shape.grid_h > max_h:
                problems.append(
                    f"{where}: board {shape.grid_w}x{shape.grid_h} exceeds "
                    f"{max_w}x{max_h}")
            if not grads[0] <= n_grads <= grads[1]:
                problems.append(f"{where}: {n_grads} gradients, wanted {grads}")
            if not cells[0] <= n_cells <= cells[1]:
                problems.append(f"{where}: {n_cells} cells, wanted {cells}")

            comp_g, span_r, span_c = component_span(shape)
            if span_r * span_c > SPAN_AREA_LIMIT:
                problems.append(
                    f"{where}: largest crossing cluster ({comp_g} gradients) "
                    f"spans {span_r}r x {span_c}c = {span_r * span_c}, over the "
                    f"{SPAN_AREA_LIMIT} the gamut can colour. Trim one axis, or "
                    f"split the cluster by removing a crossing")

            for gi, grad in enumerate(shape.gradients):
                if len(grad.cells) < 2:
                    problems.append(
                        f"{where}: gradient {gi} is {len(grad.cells)} cell(s)")
                if reversible(shape, gi):
                    problems.append(
                        f"{where}: gradient {gi} ({len(grad.cells)} cells) has "
                        f"crossings symmetric about its centre, so it reads the "
                        f"same laid down backwards")

            if tip:
                if "—" in tip or "–" in tip:
                    problems.append(f"{where}: tip uses a dash")
                for word in ("both ends", "same length", "exactly", "every "):
                    if word in tip.lower():
                        problems.append(
                            f"{where}: tip may be claiming something about the "
                            f"board ({word!r}), which nothing enforces")

            rows.append((level, name, shape.grid_w, shape.grid_h, n_grads, n_cells))

    for level, name, w, h, g, c in rows:
        print(f"  {level:3d} {name:14s} {w:2d}x{h}  grads={g:2d}  cells={c:2d}")

    print(f"\n  {len(rows)} shapes, {total_cells} cells")
    if problems:
        print(f"\n  {len(problems)} problems:")
        for p in problems:
            print(f"    {p}")
        return 1
    print("  no structural problems")
    return 0


if __name__ == "__main__":
    sys.exit(main())
