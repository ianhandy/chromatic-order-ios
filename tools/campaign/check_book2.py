"""Independent structural check on book two's authored chapters.

Written separately from the authoring pass on purpose. Twice in this project a
second implementation of a rule disagreed with the first and the disagreement
was the bug (the lazy-generator step check, and the reversal test that judged a
run in isolation), so the shapes get checked by code that did not draw them.

This only looks at authored structure. Colour fairness, run orientation and
uniqueness are build.py's job, and the app test target independently verifies
the generated result. What this catches is the cheaper class of mistake: a
missing shape, malformed drawing, one-cell gradient, or chapter whose geometry
quietly wanders outside its intended envelope.

    python3 check_book2.py
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import art  # noqa: E402

# (module, chapter title, first level, last level, max width, max height,
#  gradient range, cell range)
CHAPTERS = [
    ("book2.ch13_red_herrings", "Red Herrings", 101, 120, 11, 6, (3, 8), (11, 35)),
    ("book2.ch08_workshop", "Workshop", 121, 140, 11, 9, (6, 8), (22, 37)),
    ("book2.ch09_orchestra", "Orchestra", 141, 160, 12, 13, (7, 9), (28, 46)),
    ("book2.ch10_circuitry", "Circuitry", 161, 180, 14, 9, (7, 11), (28, 49)),
    ("book2.ch11_interiors", "Interiors", 181, 200, 17, 17, (7, 10), (31, 60)),
    ("book2.ch12_grand_works", "Grand Works", 201, 220, 17, 17, (7, 11), (35, 60)),
]

def main() -> int:
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

            if not name.strip():
                problems.append(f"{where}: empty authoring name")

            if shape.grid_w > max_w or shape.grid_h > max_h:
                problems.append(
                    f"{where}: board {shape.grid_w}x{shape.grid_h} exceeds "
                    f"{max_w}x{max_h}")
            if not grads[0] <= n_grads <= grads[1]:
                problems.append(f"{where}: {n_grads} gradients, wanted {grads}")
            if not cells[0] <= n_cells <= cells[1]:
                problems.append(f"{where}: {n_cells} cells, wanted {cells}")

            for gi, grad in enumerate(shape.gradients):
                if len(grad.cells) < 2:
                    problems.append(
                        f"{where}: gradient {gi} is {len(grad.cells)} cell(s)")

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
