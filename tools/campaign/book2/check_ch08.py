import sys, importlib
sys.path.insert(0, '/Users/ianhandy/Programming/repos/chromatic-order-ios/tools/campaign')
sys.path.insert(0, '/Users/ianhandy/Programming/repos/chromatic-order-ios/tools/campaign/book2')
import art
mod = importlib.import_module(sys.argv[1] if len(sys.argv) > 1 else 'ch08_workshop')

ok = True
for name, drawing, tip in mod.SHAPES:
    try:
        s = art.parse(drawing, name)
    except Exception as e:
        print("PARSE FAIL", name, e); ok = False; continue
    cells = len(s.all_cells)
    probs = []
    if s.grid_w > 9 or s.grid_h > 7:
        probs.append("board %dx%d" % (s.grid_w, s.grid_h))
    if not (20 <= cells <= 32):
        probs.append("cells %d" % cells)
    if not (6 <= len(s.gradients) <= 8):
        probs.append("grads %d" % len(s.gradients))
    for g in s.gradients:
        n = len(g.cells)
        if n < 2:
            probs.append("%s len %d" % (g.letter, n))
        P = {i for i, c in enumerate(g.cells) if c in s.cross_cells}
        if not P:
            probs.append("%s no crossing" % g.letter)
        elif P == {n - 1 - i for i in P}:
            probs.append("%s sym %s of %d" % (g.letter, sorted(P), n))
        if n == 2:
            probs.append("%s len2" % g.letter)
    if probs:
        ok = False
        print("FAIL", name, "; ".join(probs))
    else:
        print("ok   %-12s %dx%d  %d grads  %d cells" % (name, s.grid_w, s.grid_h, len(s.gradients), cells))
print("ALL PASS" if ok else "PROBLEMS")
