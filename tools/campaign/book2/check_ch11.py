"""Checker for chapter 11 shapes: parse + run-symmetry + budget."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import art


def check(shapes, w_max=11, h_max=9, g_lo=8, g_hi=10, c_lo=28, c_hi=42):
    ok = True
    for name, drawing, tip in shapes:
        try:
            s = art.parse(drawing, name)
        except art.ArtError as e:
            print(f"FAIL parse {name}: {e}")
            ok = False
            continue
        cells = len(s.all_cells)
        ng = len(s.gradients)
        problems = []
        if s.grid_w > w_max or s.grid_h > h_max:
            problems.append(f"dims {s.grid_w}x{s.grid_h}")
        if not (g_lo <= ng <= g_hi):
            problems.append(f"gradients {ng}")
        if not (c_lo <= cells <= c_hi):
            problems.append(f"cells {cells}")
        for g in s.gradients:
            n = len(g.cells)
            P = {i for i, cell in enumerate(g.cells) if cell in s.cross_cells}
            if n < 2:
                problems.append(f"{g.letter}: len {n}")
            if n == 2:
                problems.append(f"{g.letter}: len 2 (prefer 3+)")
            if not P:
                problems.append(f"{g.letter}: no crossings")
            elif P == {n - 1 - i for i in P}:
                problems.append(f"{g.letter}: symmetric crossings {sorted(P)} in len {n}")
        if problems:
            ok = False
            print(f"FAIL {name} [{s.grid_w}x{s.grid_h} g={ng} cells={cells}]: " + "; ".join(problems))
        else:
            print(f"ok   {name:<12} {s.grid_w}x{s.grid_h}  g={ng}  cells={cells}")
    return ok


if __name__ == "__main__":
    mod = sys.argv[1] if len(sys.argv) > 1 else "ch11_interiors"
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    m = __import__(mod)
    shapes = m.SHAPES
    print(f"{len(shapes)} shapes")
    good = check(shapes)
    print("ALL PASS" if good and len(shapes) == 20 else "PROBLEMS")
