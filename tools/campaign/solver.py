"""Uniqueness solver — Python mirror of Core/PuzzleSolver.findPlacements.

Same three gates as the Swift solver:
  * per-cell match: a bank swatch may go in a cell only if delta-E < 2
  * bank equivalence classes: two placements that differ only by swapping
    perceptually identical swatches count as one placement
  * Rule 2 step consistency: for every consecutive pair on a gradient the
    placed delta must equal the spec delta within delta-E 2

`count_placements(level, limit=2) == 1` means the puzzle has exactly one
solution a player can arrive at by looking at colors. The XCTest audit
runs the real Swift solver over the same JSON as ground truth.
"""

from __future__ import annotations

from oklch import OKLCh, dist, to_lab, lab_dist


class Puzzle:
    """Minimal stand-in for the Swift `Puzzle` the solver needs."""

    def __init__(self, gradients):
        # gradients: list of [(r, c, OKLCh, locked)] in gradient order
        self.gradients = gradients

    def free_cells(self):
        out, seen = [], set()
        for g in self.gradients:
            for (r, c, color, locked) in g:
                if locked:
                    continue
                if (r, c) in seen:
                    continue
                seen.add((r, c))
                out.append((r, c, color))
        return out

    def bank_colors(self):
        return [color for (_, _, color) in self.free_cells()]


def _bank_classes(bank):
    parent = list(range(len(bank)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for i in range(len(bank)):
        for j in range(i + 1, len(bank)):
            if dist(bank[i], bank[j]) < 2:
                parent[find(i)] = find(j)
    return [find(i) for i in range(len(bank))]


def placements(puzzle: Puzzle, limit: int = 2) -> list[dict[tuple[int, int], OKLCh]]:
    """Up to `limit` distinct placements, each as {(r, c): colour}."""
    free = puzzle.free_cells()
    bank = puzzle.bank_colors()
    out = []
    for assignment in _search(puzzle, limit):
        out.append({(free[j][0], free[j][1]): bank[assignment[j]]
                    for j in range(len(free))})
    return out


def count_placements(puzzle: Puzzle, limit: int = 2) -> int:
    return len(_search(puzzle, limit))


def _search(puzzle: Puzzle, limit: int) -> list[tuple[int, ...]]:
    free = puzzle.free_cells()
    n = len(free)
    bank = puzzle.bank_colors()
    if n == 0:
        return [()]

    locked = {}
    for g in puzzle.gradients:
        for (r, c, color, is_locked) in g:
            if is_locked:
                locked[(r, c)] = color

    adj = [[i for i in range(n) if dist(bank[i], free[j][2]) < 2] for j in range(n)]
    labels = _bank_classes(bank)

    # Precompute spec lab deltas per gradient pair.
    spec_pairs = []
    for g in puzzle.gradients:
        if len(g) < 2:
            continue
        for i in range(len(g) - 1):
            r0, c0, col0, _ = g[i]
            r1, c1, col1, _ = g[i + 1]
            s0, s1 = to_lab(col0), to_lab(col1)
            spec_pairs.append(
                ((r0, c0), (r1, c1), (s1[0] - s0[0], s1[1] - s0[1], s1[2] - s0[2]))
            )

    cell_slot = {(r, c): j for j, (r, c, _) in enumerate(free)}

    order = sorted(range(n), key=lambda j: len(adj[j]))
    used = [False] * n
    assignment = [-1] * n
    seen_vectors = {}
    state = {"done": False}

    def step_consistent():
        placed = dict(locked)
        for j in range(n):
            r, c, _ = free[j]
            placed[(r, c)] = bank[assignment[j]]
        for (a, b, spec) in spec_pairs:
            p0, p1 = placed.get(a), placed.get(b)
            if p0 is None or p1 is None:
                return False
            l0, l1 = to_lab(p0), to_lab(p1)
            actual = (l1[0] - l0[0], l1[1] - l0[1], l1[2] - l0[2])
            if lab_dist(actual, spec) >= 2:
                return False
        return True

    def backtrack(depth):
        if state["done"]:
            return
        if depth == n:
            if not step_consistent():
                return
            vec = tuple(labels[assignment[j]] for j in range(n))
            if vec not in seen_vectors:
                seen_vectors[vec] = tuple(assignment)
                if len(seen_vectors) >= limit:
                    state["done"] = True
            return
        j = order[depth]
        for i in adj[j]:
            if used[i]:
                continue
            used[i] = True
            assignment[j] = i
            backtrack(depth + 1)
            used[i] = False
            assignment[j] = -1
            if state["done"]:
                return

    _ = cell_slot
    backtrack(0)
    return list(seen_vectors.values())


def is_unique(puzzle: Puzzle) -> bool:
    return count_placements(puzzle, limit=2) == 1
