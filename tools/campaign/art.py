"""ASCII-art shape parser.

Each campaign shape is drawn as a small ASCII grid:

    '.'      empty cell (dead board)
    'a'..'z' a gradient — every cell of one letter forms one straight
             horizontal or vertical run
    '+'      a crossing cell, shared by the horizontal run and the
             vertical run that pass through it

Example (a plus sign made of two gradients that share their middle):

    ..a..
    bb+bb
    ..a..

The parser returns gradients as ordered cell lists (left-to-right for
horizontal, top-to-bottom for vertical), cropped to the drawing's
bounding box so the shipped grid is exactly as tight as the shape.
"""

from __future__ import annotations

from dataclasses import dataclass

EMPTY = "."
CROSS = "+"


@dataclass
class Gradient:
    letter: str
    direction: str          # "h" | "v"
    cells: list[tuple[int, int]]   # ordered (r, c)


@dataclass
class Shape:
    grid_w: int
    grid_h: int
    gradients: list[Gradient]
    cross_cells: set[tuple[int, int]]

    @property
    def all_cells(self) -> set[tuple[int, int]]:
        out = set()
        for g in self.gradients:
            out.update(g.cells)
        return out


class ArtError(ValueError):
    pass


def parse(art: str, name: str = "?") -> Shape:
    rows = [line for line in art.strip("\n").split("\n")]
    rows = [line.rstrip() for line in rows]
    if not rows:
        raise ArtError(f"{name}: empty art")
    width = max(len(line) for line in rows)
    grid = [line.ljust(width, EMPTY) for line in rows]

    letters: dict[str, list[tuple[int, int]]] = {}
    crosses: set[tuple[int, int]] = set()
    for r, line in enumerate(grid):
        for c, ch in enumerate(line):
            if ch == EMPTY:
                continue
            if ch == CROSS:
                crosses.add((r, c))
            elif ch.isalpha():
                letters.setdefault(ch, []).append((r, c))
            else:
                raise ArtError(f"{name}: unexpected char {ch!r} at {r},{c}")

    if not letters:
        raise ArtError(f"{name}: no gradients")

    rows_n, cols_n = len(grid), width

    def at(r: int, c: int) -> str:
        if 0 <= r < rows_n and 0 <= c < cols_n:
            return grid[r][c]
        return EMPTY

    gradients: list[Gradient] = []
    for letter in sorted(letters):
        cells = letters[letter]
        rs = {r for r, _ in cells}
        cs = {c for _, c in cells}
        if len(rs) == 1 and len(cs) == 1:
            # Single lettered cell — the run's direction comes from which
            # side its crossings sit on (a rung between two rails).
            r, c = cells[0]
            horiz = at(r, c - 1) == CROSS or at(r, c + 1) == CROSS
            vert = at(r - 1, c) == CROSS or at(r + 1, c) == CROSS
            if horiz == vert:
                raise ArtError(
                    f"{name}: gradient {letter!r} is one cell with "
                    f"{'ambiguous' if horiz else 'no'} crossings")
            direction = "h" if horiz else "v"
        elif len(rs) == 1:
            direction = "h"
        elif len(cs) == 1:
            direction = "v"
        else:
            raise ArtError(f"{name}: gradient {letter!r} is not a straight line")

        if direction == "h":
            r = next(iter(rs))
            lo, hi = min(cs), max(cs)
            # A run may start or end on a crossing it shares with a
            # perpendicular run, so walk outward through '+' cells.
            while at(r, lo - 1) == CROSS:
                lo -= 1
            while at(r, hi + 1) == CROSS:
                hi += 1
            span = [(r, c) for c in range(lo, hi + 1)]
        else:
            c = next(iter(cs))
            lo, hi = min(rs), max(rs)
            while at(lo - 1, c) == CROSS:
                lo -= 1
            while at(hi + 1, c) == CROSS:
                hi += 1
            span = [(r, c) for r in range(lo, hi + 1)]

        if len(span) < 2:
            raise ArtError(f"{name}: gradient {letter!r} has {len(span)} cell(s)")
        for (r, c) in span:
            ch = grid[r][c]
            if ch != letter and ch != CROSS:
                raise ArtError(
                    f"{name}: gradient {letter!r} is broken at {r},{c} (found {ch!r})")
        gradients.append(Gradient(letter=letter, direction=direction, cells=span))

    # Every crossing must be spanned by exactly one h run and one v run.
    for cell in sorted(crosses):
        owners = [g for g in gradients if cell in g.cells]
        dirs = sorted(g.direction for g in owners)
        if dirs != ["h", "v"]:
            raise ArtError(
                f"{name}: crossing at {cell} owned by {[g.letter for g in owners]} "
                f"(dirs {dirs}) — needs exactly one h and one v")

    # A cell shared by two gradients must be drawn as a crossing, so the
    # art always reads honestly.
    seen: dict[tuple[int, int], list[str]] = {}
    for g in gradients:
        for cell in g.cells:
            seen.setdefault(cell, []).append(g.letter)
    for cell, owners in seen.items():
        if len(owners) > 1 and cell not in crosses:
            raise ArtError(f"{name}: cell {cell} shared by {owners} but not marked '+'")

    # Crop to the bounding box.
    used = sorted(seen)
    min_r = min(r for r, _ in used)
    min_c = min(c for _, c in used)
    max_r = max(r for r, _ in used)
    max_c = max(c for _, c in used)
    for g in gradients:
        g.cells = [(r - min_r, c - min_c) for (r, c) in g.cells]
    crosses = {(r - min_r, c - min_c) for (r, c) in crosses}

    return Shape(
        grid_w=max_c - min_c + 1,
        grid_h=max_r - min_r + 1,
        gradients=gradients,
        cross_cells=crosses,
    )


def crossing_graph(shape: Shape) -> dict[int, list[tuple[int, int, int]]]:
    """gradient index -> [(other index, my pos, other pos), ...]."""
    out: dict[int, list[tuple[int, int, int]]] = {i: [] for i in range(len(shape.gradients))}
    for i, g in enumerate(shape.gradients):
        for j, other in enumerate(shape.gradients):
            if i == j:
                continue
            shared = set(g.cells) & set(other.cells)
            for cell in shared:
                out[i].append((j, g.cells.index(cell), other.cells.index(cell)))
    return out
