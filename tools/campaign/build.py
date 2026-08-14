"""Build the campaign: shapes in, campaign.json (+ a contact sheet) out.

    python3 build.py            # write ChromaticOrder/Resources/campaign.json
    python3 build.py --sheet    # also render campaign-sheet.png to review
    python3 build.py --level 42 # rebuild/report one level only

For each level this:
  1. parses the ASCII art into gradients,
  2. paints every gradient with an OKLCh ramp — one family per gradient,
     and where two gradients cross, the crossing cell's colour is solved
     for so both ramps agree on it,
  3. validates the palette (usable band, sRGB gamut, per-step delta-E,
     pairwise delta-E floor between every pair of cells on the board),
  4. reveals starter cells until the board has exactly one solution by
     the same rules Core/PuzzleSolver.swift uses,
  5. emits the doc in the app's CreatorPuzzleDoc schema.

Difficulty ramps by level: bigger boards, smaller steps, tighter
delta-E floor, more channels in play, fewer given cells.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import statistics
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import art
import shapes
from oklch import (OKLCh, dist, in_gamut, in_usable_band, norm_h, to_lab,
                   to_srgb8)
from solver import Puzzle, count_placements, placements

ROOT = Path(__file__).resolve().parents[2]
OUT_JSON = ROOT / "ChromaticOrder" / "Resources" / "campaign.json"
OUT_SHEET = Path(__file__).resolve().parent / "campaign-sheet.png"

TOTAL_LEVELS = 200

# The colour curve finishes at level 100, and the second hundred inherits its
# end state rather than continuing to tighten.
#
# This is a measured limit, not a stylistic choice. Level 100's step floor of
# 5.4 delta-E is already the smallest step the long runs can pay for: a nine
# cell frame at 6.0 per step needs about 46 delta-E of travel, which leaves the
# sRGB gamut entirely, and pushing the floor to 6.2 or 5.8 made Reactor
# unbuildable. Simulated play puts a typical player near 84% at these steps and
# collapsing to about 20% below three times the eye's noise. So there is no room
# below here that is both reachable in sRGB and fair to a person.
#
# Book two therefore gets harder structurally instead: more gradients, denser
# crossing graphs, bigger boards. Those raise the bookkeeping load without
# asking the eye to make a finer call than it already makes on level 100.
COLOUR_CURVE_END = 100

# Playable sub-band. Tighter than OK's full usable band so ramps never
# sit against the edge where sRGB clipping starts flattening steps.
L_LO, L_HI = 0.30, 0.82
C_LO, C_HI = 0.055, 0.26
# Hue ramps need enough chroma for a hue step to read as a colour change.
C_HUE_MIN = 0.11


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def curve(level: int) -> dict:
    """Per-level difficulty knobs."""
    # Clamped, so levels 1-100 are byte for byte what they were before book two
    # existed and 101-200 hold at the level-100 palette settings. See
    # COLOUR_CURVE_END for why the curve stops rather than continuing.
    t = min(1.0, (level - 1) / (COLOUR_CURVE_END - 1))
    ch = shapes.chapter_of(level)[0]
    # Perceptual floor between any two cells on the board. Starts far
    # above "obviously different" and lands just above the procedural
    # generator's own 5.0 minimum.
    de_floor = lerp(16.0, 6.5, t ** 0.85)
    # Target delta-E per step inside a gradient, and the hard floor no
    # step anywhere on the board may go under. The floor is what keeps a
    # level honest: below ~4.5 two neighbours stop being tellable apart.
    # The band matches what the procedural generator produces across its
    # own tiers (Trivial steps read at 9-13, Expert at 5-7).
    step_target = lerp(15.0, 8.0, t ** 0.8)
    # Measured against simulated play: with a step under three times the
    # eye's noise, success collapses to about 20%, and between three and five
    # times it recovers to about 84%. At a plausible noise of 2 that argues for
    # 6, and 6 is what the long runs cannot pay for: a nine-cell frame at 6 per
    # step needs about 46 delta-E of travel, which leaves the sRGB gamut, and
    # Reactor became unbuildable at both 6.2 and 5.8. So the floor stays at
    # 5.4 and the partition rule below carries the fairness work instead.
    step_floor = lerp(9.5, 5.4, t ** 0.7)
    # How many cells the player is handed. Grows more slowly than the
    # boards do, so late levels feel open without ever being unfair. This is
    # a target, not a promise: `choose_locks` will hand out more given cells
    # when that is what makes a board deducible.
    bank_target = round(lerp(1, 30, t ** 1.15))
    if level > COLOUR_CURVE_END:
        # Book two needs its own bank curve, because `t` is clamped and would
        # otherwise hold all hundred of its levels at 30 — the far end of book
        # one's ramp, held flat for a hundred levels. That is not a difficulty
        # curve, and it is the single thing that made book two unplayable.
        #
        # Bank size is the knob that matters here, by a wide margin. Measured
        # over all of book two at fixed palettes and fixed shapes, changing
        # nothing but how many cells are given: a typical eye's first pass goes
        # from 3% of boards correct at 30 swatches to 30% at 20 and 52% at 16,
        # and the cells it leaves wrong go from 14.0 to 3.3 to 1.6.
        #
        # That last number is the real cost, because campaign levels play as
        # zen: no Check, no hearts, the board simply clicks when it is right.
        # A wrong first pass is not a loss, it is a blind hunt back through
        # everything already placed, with nothing on screen saying which cells
        # are wrong. Fourteen of those is not a hard level, it is an unreadable
        # one. Perfect-eye play tells the same story from the other end: at 30
        # the reasoning solver itself misses 13 boards, at 20 and below it
        # misses none, so those misses were thirty near-certain decisions
        # compounding rather than anything wrong with the boards.
        #
        # Colour cannot carry this instead: a field spanning ten columns can
        # afford (L_HI - L_LO) * 0.88 * 100 / 10 = 4.6 delta-E per step, and
        # lightness is the widest channel there is. Searching forty palettes
        # per level instead of taking the first lifts the step by 0.08, and
        # widening the band to the app's own limit lifts a typical eye by one
        # point while making two levels unbuildable. Book two already has the
        # steps sRGB allows at these spans.
        #
        # Sawtoothed on purpose: each chapter opens easier than the last one
        # closed, then ramps to its own finale.
        _title, first, last, _blurb = shapes.chapter_of(level)
        stage = [c[0] for c in shapes.CHAPTERS
                 if c[1] > COLOUR_CURVE_END].index(ch)
        u = (level - first) / max(1, last - first)
        bank_target = round(lerp(14 + stage, 20 + 2 * stage, u))
    # The gap a cell must have from every other colour on the board when
    # deduction cannot reach it, so the player is never asked to trust their
    # eye on a call finer than this. Deduced cells are allowed to be tighter,
    # because there the player computes the answer instead of seeing it.
    eye_floor = lerp(12.0, 7.0, t ** 0.8)
    # Applied only to Landmarks, which is where the measurement found the
    # defect: that chapter's failing levels are wide scenes made of many short
    # parallel runs (Fountain's jets, Garden's beds, Harbor's masts) and they
    # were losing the grouping judgement, with runs approaching to 4.2 delta-E
    # against 14 in the opening chapters. It cannot be global: Reactor's
    # concentric frames carry eight long runs, only about 180 of 4000 painting
    # attempts survive the gamut at all, and this rule rejects every one of
    # them, so the shape stops building.
    #
    # The partition condition, expressed relative to the runs themselves
    # rather than as an absolute delta-E. A player groups swatches by run
    # before ordering them, so two runs must be at least as easy to tell apart
    # as the neighbours inside one run are. An absolute floor cannot work here:
    # a lattice's adjacent rows differ by exactly one row-step by construction,
    # so any floor above that step makes every lattice unbuildable, and yet
    # lattices measured fine (100% with a perfect eye). Tying the demand to the
    # step makes it self-scaling instead.
    #
    # Book two's chapters get it too, at a slightly gentler ratio. Their boards
    # are built from exactly the morphology that failed in Landmarks (a bus with
    # runs tapping into it, a row of columns, a lattice of members), and with the
    # colour curve now flat, partition is the only fairness lever left. It is not
    # a hard demand there: `build_level` walks the ratio down as attempts run
    # out, so a shape that genuinely cannot pay for it still builds, and reports
    # that it did.
    sep_ratio = 0.9 if ch == "Landmarks" else (0.8 if level > COLOUR_CURVE_END else 0.0)
    if ch == "First Steps":
        channels = ["L"]
        two_channel = 0.0
    elif ch == "Two Strokes":
        channels = ["L", "h"]
        two_channel = 0.0
    elif ch == "Crossings":
        channels = ["L", "h"]
        two_channel = 0.0
    elif ch == "Everyday Things":
        # Still lightness and hue only. Chroma is introduced by name in
        # chapter 5 ("Fish"), and a channel shouldn't turn up 20 levels
        # before the tip that explains it — this chapter's step up is size
        # and step size, which is what its blurb says.
        channels = ["L", "h"]
        two_channel = 0.0
    elif ch == "Creatures":
        channels = ["L", "h", "c"]
        two_channel = 0.15
    elif ch == "Landmarks":
        channels = ["L", "h", "c"]
        two_channel = 0.35
    else:
        channels = ["L", "h", "c"]
        two_channel = 0.6
    return dict(de_floor=de_floor, step_target=step_target,
                step_floor=step_floor, bank_target=bank_target,
                eye_floor=eye_floor, sep_ratio=sep_ratio,
                channels=channels, two_channel=two_channel, chapter=ch)


# ─── Ramps ─────────────────────────────────────────────────────────

class Ramp:
    """A gradient's colour line: start plus a per-cell delta."""

    def __init__(self, L0, c0, h0, dL, dc, dh):
        self.L0, self.c0, self.h0 = L0, c0, h0
        self.dL, self.dc, self.dh = dL, dc, dh

    def at(self, i: int) -> OKLCh:
        return OKLCh(self.L0 + i * self.dL,
                     self.c0 + i * self.dc,
                     self.h0 + i * self.dh)

    def colors(self, n: int) -> list[OKLCh]:
        return [self.at(i) for i in range(n)]


def step_delta_for(channel: str, target_de: float, chroma: float) -> float:
    """Channel delta that produces roughly `target_de` per step."""
    if channel == "L":
        return target_de / 100.0
    if channel == "c":
        return target_de / 100.0
    # Hue: arc length in OKLab is chroma * angle.
    usable_c = max(chroma, C_HUE_MIN)
    return math.degrees(target_de / (100.0 * usable_c))


def step_de(channel: str, delta: float, chroma: float) -> float:
    if channel in ("L", "c"):
        return abs(delta) * 100.0
    return abs(math.radians(delta)) * 100.0 * max(chroma, 1e-6)


HUE_SPAN_CAP = 150.0   # degrees a single gradient may sweep
# A lattice field is read as a field, so its rows may sweep further.
HUE_FIELD_CAP = 210.0


def feasible_step_de(channel: str, length: int, chroma: float) -> float:
    """Largest per-step delta-E this channel can give a run this long.

    A seven-cell lightness ramp only has the whole L range to spend, so
    its steps are necessarily finer than a three-cell ramp's. Difficulty
    knobs get clamped to this before anything is validated against them.
    """
    steps = max(1, length - 1)
    if channel == "L":
        return (L_HI - L_LO) * 100.0 / steps
    if channel == "c":
        return (C_HI - C_LO) * 100.0 / steps
    return 100.0 * max(chroma, C_HUE_MIN) * math.radians(HUE_SPAN_CAP / steps)


_CHROMA_CAP: dict[tuple[int, int], float] = {}


def max_chroma(L: float, h: float) -> float:
    """Highest in-gamut chroma at this lightness and hue.

    sRGB is far from a cylinder: 0.26 chroma exists in yellow at L 0.85
    and nowhere near blue at L 0.4. Ramps have to be built against this
    ceiling or half of them clip on screen.
    """
    key = (int(round(L * 200)), int(round(norm_h(h) / 4)))
    hit = _CHROMA_CAP.get(key)
    if hit is not None:
        return hit
    # Evaluate at the BUCKET's centre, not at the caller's exact coordinates.
    # The cache is bucketed, so storing the first caller's value made the
    # answer depend on which caller happened to arrive first. That is invisible
    # in a sequential build and produces a different campaign the moment levels
    # are built in a different order, which is exactly what parallelism does.
    quantised_L = key[0] / 200.0
    quantised_h = (key[1] * 4) % 360
    lo, hi = 0.0, 0.42
    for _ in range(22):
        mid = (lo + hi) / 2
        if in_gamut(OKLCh(quantised_L, mid, quantised_h)):
            lo = mid
        else:
            hi = mid
    _CHROMA_CAP[key] = lo
    return lo


def chroma_ceiling(Ls, hs) -> float:
    """Chroma that stays in gamut across every (L, h) the ramp visits."""
    return min(max_chroma(L, h) for L in Ls for h in hs)


def l_window(hue: float, min_c: float = 0.10) -> tuple[float, float]:
    """Widest run of lightness where `hue` still holds `min_c` chroma.

    Deep blues run out of chroma above L 0.6; yellows below L 0.5. A
    lightness ramp has to live inside its hue's window or it goes gray at
    one end.
    """
    best = (0.0, 0.0)
    run_start = None
    L = L_LO
    while L <= L_HI + 1e-9:
        ok = max_chroma(L, hue) >= min_c
        if ok and run_start is None:
            run_start = L
        if (not ok or L > L_HI - 1e-9) and run_start is not None:
            end = L if ok else L - 0.02
            if end - run_start > best[1] - best[0]:
                best = (run_start, end)
            run_start = None
        L += 0.02
    return best


def free_ramp(rng, length, channel, family_hue, cfg, target, second=None) -> Ramp | None:
    """Ramp for a gradient with no crossings to already-painted work."""
    steps = max(1, length - 1)
    ramp = None
    if channel == "L":
        win_lo, win_hi = l_window(family_hue, 0.095)
        if win_hi - win_lo < 0.08:
            return _fail("free_ramp_no_l_window")
        for _ in range(10):
            delta = min(step_delta_for("L", target * rng.uniform(0.9, 1.1), 0),
                        (win_hi - win_lo) / steps)
            if rng.random() < 0.5:
                delta = -delta
            span = abs(delta) * steps
            lo = win_lo if delta > 0 else win_lo + span
            hi = win_hi - span if delta > 0 else win_hi
            if hi < lo:
                continue
            L0 = rng.uniform(lo, hi)
            Ls = [L0 + i * delta for i in range(length)]
            ceiling = chroma_ceiling(Ls, [family_hue]) * 0.9
            if ceiling < 0.085:
                continue
            c0 = rng.uniform(0.085, min(0.20, ceiling))
            ramp = Ramp(L0, c0, family_hue, delta, 0.0, 0.0)
            break
    elif channel == "c":
        for _ in range(10):
            L0 = rng.uniform(0.42, 0.74)
            ceiling = min(C_HI, max_chroma(L0, family_hue) * 0.9)
            if ceiling - C_LO < 0.05:
                continue
            delta = min(step_delta_for("c", target * rng.uniform(0.9, 1.1), 0),
                        (ceiling - C_LO) / steps)
            if rng.random() < 0.5:
                delta = -delta
            span = abs(delta) * steps
            lo = C_LO if delta > 0 else C_LO + span
            hi = ceiling - span if delta > 0 else ceiling
            if hi < lo:
                continue
            c0 = rng.uniform(lo, hi)
            ramp = Ramp(L0, c0, family_hue, 0.0, delta, 0.0)
            break
    else:  # hue
        for _ in range(10):
            L0 = rng.uniform(0.46, 0.74)
            # Provisional chroma sets the step size, so solve the sweep
            # and the ceiling together: wider sweeps see more of the
            # gamut and so allow less chroma.
            c_guess = rng.uniform(C_HUE_MIN, 0.20)
            delta = step_delta_for("h", target * rng.uniform(0.9, 1.1), c_guess)
            if abs(delta) * steps > HUE_SPAN_CAP:
                delta = HUE_SPAN_CAP / steps
            if rng.random() < 0.5:
                delta = -delta
            h0 = family_hue - delta * steps / 2.0
            hs = [h0 + i * delta for i in range(length)]
            ceiling = chroma_ceiling([L0], hs) * 0.9
            if ceiling < C_HUE_MIN:
                continue
            c0 = min(c_guess, ceiling)
            # Chroma came down, so the hue step has to grow to hold the
            # same perceptual step.
            delta = math.copysign(
                min(abs(step_delta_for("h", target, c0)), HUE_SPAN_CAP / steps),
                delta)
            h0 = family_hue - delta * steps / 2.0
            ramp = Ramp(L0, c0, h0, 0.0, 0.0, delta)
            break
    if ramp is None:
        return _fail("free_ramp_gamut")

    if second and rng.random() < cfg["two_channel"]:
        # Add a gentle secondary channel so late levels stop being
        # readable off one axis alone.
        extra = cfg["step_target"] * 0.35 / 100.0
        if second == "L" and channel != "L":
            ramp.dL = extra * (1 if rng.random() < 0.5 else -1)
            if not (L_LO <= ramp.L0 + ramp.dL * (length - 1) <= L_HI):
                ramp.dL = -ramp.dL
        elif second == "c" and channel != "c":
            ramp.dc = extra * (1 if rng.random() < 0.5 else -1)
            if not (C_LO <= ramp.c0 + ramp.dc * (length - 1) <= C_HI):
                ramp.dc = -ramp.dc
    return ramp


def pinned_ramp(rng, length, pins, channel, cfg, target) -> Ramp | None:
    """Ramp forced through one or two already-painted crossing cells."""
    pins = sorted(pins)
    (j0, p0) = pins[0]
    if len(pins) == 1:
        # Inherit the fixed channels from the crossing, ramp a different
        # channel than the gradient we cross, so the two never look like
        # continuations of each other.
        target = target * rng.uniform(0.9, 1.1)
        steps = max(1, length - 1)

        def usable(ramp: Ramp) -> bool:
            for i in range(length):
                col = ramp.at(i)
                if not (L_LO <= col.L <= L_HI and C_LO <= col.c <= C_HI):
                    return False
                if not in_gamut(OKLCh(col.L, col.c, norm_h(col.h))):
                    return False
            return True

        if channel == "L":
            delta = step_delta_for("L", target, p0.c)
            for scale in (1.0, 0.75, 0.55):
                for sign in ([1, -1] if rng.random() < 0.5 else [-1, 1]):
                    cand = Ramp(p0.L - j0 * delta * sign * scale, p0.c, p0.h,
                                delta * sign * scale, 0.0, 0.0)
                    if usable(cand):
                        return cand
            return _fail("pin_L")
        if channel == "c":
            delta = step_delta_for("c", target, 0)
            for scale in (1.0, 0.75, 0.55):
                for sign in ([1, -1] if rng.random() < 0.5 else [-1, 1]):
                    cand = Ramp(p0.L, p0.c - j0 * delta * sign * scale, p0.h,
                                0.0, delta * sign * scale, 0.0)
                    if usable(cand):
                        return cand
            return _fail("pin_c")
        if p0.c < C_HUE_MIN:
            return _fail("pin_h_flat")
        delta = min(step_delta_for("h", target, p0.c), HUE_SPAN_CAP / steps)
        for scale in (1.0, 0.75, 0.55):
            for sign in ([1, -1] if rng.random() < 0.5 else [-1, 1]):
                d = delta * sign * scale
                cand = Ramp(p0.L, p0.c, p0.h - j0 * d, 0.0, 0.0, d)
                if usable(cand):
                    return cand
        return _fail("pin_h")

    # Two or more pins: the line through the first two is forced.
    (j1, p1) = pins[1]
    if j1 == j0:
        return _fail("pin_same_pos")
    # Hue takes the short way round so a crossing pair never sweeps the
    # long arc between two nearby hues.
    h0, h1 = p0.h, p1.h
    while h1 - h0 > 180:
        h1 -= 360
    while h1 - h0 < -180:
        h1 += 360
    span = j1 - j0
    dL = (p1.L - p0.L) / span
    dc = (p1.c - p0.c) / span
    dh = (h1 - h0) / span
    ramp = Ramp(p0.L - j0 * dL, p0.c - j0 * dc, h0 - j0 * dh, dL, dc, dh)
    # Any further pins must already sit on that line.
    for (j, p) in pins[2:]:
        got = ramp.at(j)
        if dist(OKLCh(got.L, got.c, norm_h(got.h)), OKLCh(p.L, p.c, norm_h(p.h))) > 1.0:
            return _fail("pin_overdetermined")
    return ramp


# ─── Painting a level ──────────────────────────────────────────────

FAILS: dict[str, int] = {}


def _fail(reason: str):
    FAILS[reason] = FAILS.get(reason, 0) + 1
    return None


def components(shape: art.Shape, graph) -> list[list[int]]:
    """Groups of gradients tied together by crossings."""
    seen, out = set(), []
    for i in range(len(shape.gradients)):
        if i in seen:
            continue
        stack, comp = [i], []
        while stack:
            g = stack.pop()
            if g in seen:
                continue
            seen.add(g)
            comp.append(g)
            for (other, _, _) in graph[g]:
                if other not in seen:
                    stack.append(other)
        out.append(sorted(comp))
    return out


def affine_component(rng, shape, comp, cfg) -> dict[int, list[OKLCh]] | None:
    """Paint a fully-crossed lattice as one linear colour field.

    Three or more rows crossing three or more columns can't be painted
    gradient-by-gradient: by the time the third row is pinned, its colour
    line is already over-determined. The only exact solution is a field
    where colour varies linearly with row and with column — which also
    happens to be the nicest one to look at, because every row then shares
    a progression and every column shares a different one.

    A wide lattice spends its whole colour budget on one sweep per axis, so
    its steps have to be finer than a short run's: the target walks down
    toward the level's floor until the field fits inside sRGB.
    """
    cells = sorted({cell for gi in comp for cell in shape.gradients[gi].cells})
    r0 = min(r for r, _ in cells)
    c0 = min(c for _, c in cells)
    r_span = max(r for r, _ in cells) - r0
    c_span = max(c for _, c in cells) - c0
    # A wide lattice has to spend its whole colour budget on one sweep per
    # axis, so it is allowed slightly finer steps than the rest of the
    # level. Fair trade: a lattice hands the player a crossing on every
    # row and column, which is far more information than a lone ramp.
    slack = 0.82 if max(r_span, c_span) >= 7 else 1.0
    floor = max(3.9, cfg["step_floor"] * slack)
    cfg["field_floor"] = min(cfg.get("field_floor", 99.0), floor)

    def reach_ok(channel, span):
        """Can this channel make a readable step over this many cells?"""
        if span == 0:
            return True
        if channel == "L":
            return (L_HI - L_LO) * 0.88 / span * 100 >= floor
        if channel == "c":
            return (C_HI - C_LO) * 0.85 / span * 100 >= floor
        return 100 * 0.14 * math.radians(HUE_FIELD_CAP / span) >= floor

    pairs = [(a, b) for a in ("L", "h", "c") for b in ("L", "h", "c")
             if a != b and reach_ok(a, r_span) and reach_ok(b, c_span)]
    if not pairs:
        return _fail("affine_no_channel")

    # Descending ladder: try the level's step size, then finer, never
    # below the floor.
    ladder = [cfg["step_target"] * f for f in (1.1, 0.95, 0.8, 0.68, 0.58)]
    ladder = [t for t in ladder if t >= floor] + [floor * 1.05]

    for _ in range(90):
        row_ch, col_ch = rng.choice(pairs)
        hue = rng.uniform(0, 360)
        row_sign = 1 if rng.random() < 0.5 else -1
        col_sign = 1 if rng.random() < 0.5 else -1

        for target in ladder:
            # Lightness travel is independent of everything else.
            dL_row = dL_col = 0.0
            if row_ch == "L" and r_span:
                dL_row = min(target / 100.0, (L_HI - L_LO) * 0.88 / r_span) * row_sign
            if col_ch == "L" and c_span:
                dL_col = min(target / 100.0, (L_HI - L_LO) * 0.88 / c_span) * col_sign
            travel = (abs(dL_row) * r_span + abs(dL_col) * c_span) / 2
            lo, hi = L_LO + travel, L_HI - travel
            if hi < lo:
                _fail("af_L_travel")
                continue
            base_L = min(max(rng.uniform(0.38, 0.70), lo), hi)
            L_visits = [base_L, base_L + travel, base_L - travel]

            # Hue sweep is bounded by the step size we are asking for at a
            # provisional chroma; the gamut ceiling is then measured across
            # that whole window, which is safe because a smaller sweep only
            # ever leaves more chroma available.
            sweep = 0.0
            if row_ch == "h" and r_span:
                sweep = max(sweep, min(HUE_FIELD_CAP,
                                       math.degrees(target / 14.0) * r_span))
            if col_ch == "h" and c_span:
                sweep = max(sweep, min(HUE_FIELD_CAP,
                                       math.degrees(target / 14.0) * c_span))
            hue_samples = [hue] if sweep == 0 else [
                hue - sweep / 2 + sweep * k / 8 for k in range(9)
            ]
            ceiling = chroma_ceiling(L_visits, hue_samples) * 0.88
            if ceiling < 0.095:
                _fail("af_ceiling")
                continue

            dc_row = dc_col = 0.0
            base_c = min(0.185, ceiling)
            if "c" in (row_ch, col_ch):
                top = min(C_HI, ceiling)
                if top - C_LO < 0.05:
                    _fail("af_c_range")
                    continue
                base_c = (C_LO + top) / 2
                reach = (top - C_LO) * 0.9
                if row_ch == "c" and r_span:
                    dc_row = min(target / 100.0, reach / r_span) * row_sign
                if col_ch == "c" and c_span:
                    dc_col = min(target / 100.0, reach / c_span) * col_sign

            dh_row = dh_col = 0.0
            if row_ch == "h" and r_span:
                dh_row = min(math.degrees(target / (100.0 * base_c)),
                             sweep / max(1, r_span)) * row_sign
            if col_ch == "h" and c_span:
                dh_col = min(math.degrees(target / (100.0 * base_c)),
                             sweep / max(1, c_span)) * col_sign

            start_L = base_L - (dL_row * r_span + dL_col * c_span) / 2
            start_c = base_c - (dc_row * r_span + dc_col * c_span) / 2
            start_h = hue - (dh_row * r_span + dh_col * c_span) / 2

            field = {}
            for (r, c) in cells:
                dr, dc = r - r0, c - c0
                field[(r, c)] = OKLCh(start_L + dL_row * dr + dL_col * dc,
                                      start_c + dc_row * dr + dc_col * dc,
                                      norm_h(start_h + dh_row * dr + dh_col * dc))
            if not all(in_usable_band(col) and in_gamut(col)
                       for col in field.values()):
                _fail("af_gamut")
                continue
            out = {gi: [field[cell] for cell in shape.gradients[gi].cells]
                   for gi in comp}
            worst = min(dist(cols[i], cols[i + 1])
                        for cols in out.values() for i in range(len(cols) - 1))
            if worst < floor:
                _fail("af_worst_step")
                continue
            return out

    # The widest lattices can't be done with one OKLCh channel per axis:
    # a hue axis long enough to keep its steps readable sweeps further
    # than the gamut holds chroma for. Fall back to a field that is linear
    # in OKLab instead, which is free to trade hue against chroma as it
    # goes — and reads even more smoothly, since OKLab is the space the
    # steps are measured in.
    return lab_field(rng, shape, comp, cfg, cells, r0, c0, r_span, c_span)


def lab_field(rng, shape, comp, cfg, cells, r0, c0, r_span, c_span):
    floor = cfg["step_floor"]
    ladder = [cfg["step_target"] * f for f in (1.0, 0.85, 0.7)]
    ladder = [t for t in ladder if t >= floor] + [floor * 1.06]

    for _ in range(600):
        target = rng.choice(ladder)
        # Two directions in OKLab, kept well apart so a row step and a
        # column step never look like the same move.
        def unit():
            v = [rng.gauss(0, 1) for _ in range(3)]
            v[0] *= 0.7          # lean the search away from pure lightness
            n = math.sqrt(sum(x * x for x in v)) or 1.0
            return [x / n for x in v]

        u, w = unit(), unit()
        dotp = sum(a * b for a, b in zip(u, w))
        if abs(dotp) > 0.6:
            continue
        mag = target / 100.0
        v_row = [x * mag for x in u]
        v_col = [x * mag for x in w]
        base_L = rng.uniform(0.40, 0.68)
        base_hue = rng.uniform(0, 360)
        base_c = rng.uniform(0.11, 0.17)
        base = [base_L,
                base_c * math.cos(math.radians(base_hue)),
                base_c * math.sin(math.radians(base_hue))]
        # Centre the field on the base point.
        origin = [base[k] - (v_row[k] * r_span + v_col[k] * c_span) / 2
                  for k in range(3)]

        field = {}
        ok = True
        for (r, c) in cells:
            dr, dc = r - r0, c - c0
            L = origin[0] + v_row[0] * dr + v_col[0] * dc
            a = origin[1] + v_row[1] * dr + v_col[1] * dc
            b = origin[2] + v_row[2] * dr + v_col[2] * dc
            chroma = math.hypot(a, b)
            hue = math.degrees(math.atan2(b, a))
            col = OKLCh(L, chroma, norm_h(hue))
            if not (L_LO <= L <= L_HI and C_LO <= chroma <= C_HI):
                ok = False
                break
            if not (in_usable_band(col) and in_gamut(col)):
                ok = False
                break
            field[(r, c)] = col
        if not ok:
            _fail("lab_field_range")
            continue
        out = {gi: [field[cell] for cell in shape.gradients[gi].cells]
               for gi in comp}
        worst = min(dist(cols[i], cols[i + 1])
                    for cols in out.values() for i in range(len(cols) - 1))
        if worst < floor:
            _fail("lab_field_step")
            continue
        return out
    return _fail("affine_field")


def paint(shape: art.Shape, cfg: dict, rng: random.Random) -> list[list[OKLCh]] | None:
    """Assign colours to every gradient, or None if this attempt fails."""
    n = len(shape.gradients)
    graph = art.crossing_graph(shape)

    base_hue = rng.uniform(0, 360)
    sep = 360.0 / max(n, 3)
    family = {}
    hue_slots = list(range(n))
    rng.shuffle(hue_slots)
    for idx in range(n):
        family[idx] = norm_h(base_hue + hue_slots[idx] * sep
                             + rng.uniform(-sep * 0.15, sep * 0.15))

    colors: dict[int, list[OKLCh]] = {}
    primary: dict[int, str] = {}

    # Paint order, per crossing-connected group. Whichever direction has
    # fewer gradients goes first and freely; the other direction is then
    # pinned by at most that many crossings, which is exactly what a
    # colour line can absorb. Groups where both directions have three or
    # more members are lattices and get an affine field instead.
    painted_order: list[int] = []
    for comp in components(shape, graph):
        horiz = [g for g in comp if shape.gradients[g].direction == "h"]
        vert = [g for g in comp if shape.gradients[g].direction == "v"]
        if len(horiz) >= 3 and len(vert) >= 3:
            field = affine_component(rng, shape, comp, cfg)
            if field is None:
                return None
            for gi, cols in field.items():
                colors[gi] = cols
                primary[gi] = "field"
            continue
        first, second_side = (horiz, vert) if len(horiz) <= len(vert) else (vert, horiz)
        rng.shuffle(first)
        rng.shuffle(second_side)
        painted_order.extend(first + second_side)

    for gi in painted_order:
        grad = shape.gradients[gi]
        length = len(grad.cells)
        pins = []
        partner_channels = set()
        for (other, my_pos, other_pos) in graph[gi]:
            if other in colors:
                pins.append((my_pos, colors[other][other_pos]))
                partner_channels.add(primary[other])
        # Channel choice: differ from whatever we cross, and respect the
        # channel's range (chroma can't ramp far across a long run).
        options = [c for c in cfg["channels"] if c != "c" or length <= 6]
        fresh = [c for c in options if c not in partner_channels]
        # Prefer a channel the crossed gradient isn't already using, so two
        # gradients meeting at a cell never look like one long ramp.
        pool = rng.sample(fresh, len(fresh)) if fresh else []
        pool += rng.sample([c for c in options if c not in pool],
                           len([c for c in options if c not in pool]))
        second = rng.choice([c for c in ("L", "c") if c != (pool[0] if pool else "L")]
                            or ["L"])

        cols = None
        for channel in pool:
            chroma_hint = pins[0][1].c if pins else 0.20
            headroom = feasible_step_de(channel, length, chroma_hint)
            target = min(cfg["step_target"], headroom * 0.92)
            if pins:
                ramp = pinned_ramp(rng, length, pins, channel, cfg, target)
            else:
                ramp = free_ramp(rng, length, channel, family[gi], cfg, target,
                                 second=second)
            if ramp is None:
                continue
            candidate = [OKLCh(c.L, c.c, norm_h(c.h)) for c in ramp.colors(length)]
            if not all(in_usable_band(col) and in_gamut(col) for col in candidate):
                _fail("band_gamut")
                continue
            if not all(L_LO - 0.02 <= col.L <= L_HI + 0.02 for col in candidate):
                _fail("L_range")
                continue
            if not all(C_LO - 0.01 <= col.c <= C_HI + 0.01 for col in candidate):
                _fail("c_range")
                continue
            # A channel that can't carry a readable step for this run (a
            # hue ramp at low chroma, say) is no use — try the next one
            # rather than poisoning the level.
            if min(dist(candidate[i], candidate[i + 1])
                   for i in range(length - 1)) < cfg["step_floor"]:
                _fail("cand_flat")
                continue
            cols = candidate
            primary[gi] = channel
            break
        if cols is None:
            _fail("ramp_none")
            return None
        colors[gi] = cols

    # Step sizes, level-wide. Every step has to stay readable, and none
    # may be so big the ramp reads as two unrelated colours.
    steps = [dist(cols[i], cols[i + 1])
             for cols in colors.values() for i in range(len(cols) - 1)]
    if min(steps) < min(cfg["step_floor"], cfg.get("field_floor", 99.0)):
        _fail("step_floor")
        return None
    if max(steps) > 62:
        _fail("step_ceiling")
        return None

    # Crossing cells must agree exactly (they were solved for, so this is
    # a guard against a bad pin path).
    for cell in shape.cross_cells:
        vals = []
        for gi, grad in enumerate(shape.gradients):
            if cell in grad.cells:
                vals.append(colors[gi][grad.cells.index(cell)])
        for a in vals[1:]:
            if dist(vals[0], a) > 1.0:
                _fail("crossing_mismatch")
                return None

    # Board-wide separation. The floor is capped by the finest step in
    # play, so the closest pair of colours on the board is always a pair
    # of neighbours inside one gradient — where position tells you which
    # is which. Two unrelated cells are never that close.
    # Between-run separation, skipping the cell a crossing pair shares (their
    # closest approach there is zero by construction, which is the point of a
    # crossing).
    for gi in range(len(shape.gradients)):
        for gj in range(gi + 1, len(shape.gradients)):
            common = set(shape.gradients[gi].cells) & set(shape.gradients[gj].cells)
            closest = min(
                (dist(colors[gi][a], colors[gj][b])
                 for a, ca in enumerate(shape.gradients[gi].cells)
                 if ca not in common
                 for b, cb in enumerate(shape.gradients[gj].cells)
                 if cb not in common),
                default=None)
            own_step = min(
                min((dist(colors[g][k], colors[g][k + 1])
                     for k in range(len(colors[g]) - 1)), default=99.0)
                for g in (gi, gj))
            if closest is not None and closest < own_step * cfg["sep_ratio"]:
                _fail("run_separation")
                return None

    floor = min(cfg["de_floor"], min(steps) * 0.9)
    board: dict[tuple[int, int], OKLCh] = {}
    for gi, grad in enumerate(shape.gradients):
        for pos, cell in enumerate(grad.cells):
            board.setdefault(cell, colors[gi][pos])
    keys = list(board)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            if dist(board[keys[i]], board[keys[j]]) < floor:
                _fail("pair_floor")
                return None

    return [colors[i] for i in range(n)]


# ─── Locks / uniqueness ────────────────────────────────────────────

def build_puzzle(shape, colors, locked) -> Puzzle:
    grads = []
    for gi, grad in enumerate(shape.gradients):
        grads.append([
            (r, c, colors[gi][pos], (r, c) in locked)
            for pos, (r, c) in enumerate(grad.cells)
        ])
    return Puzzle(grads)


def every_gradient_free(shape, locked) -> bool:
    return all(any((cell not in locked) for cell in g.cells) for g in shape.gradients)


def deduction_closure(shape, known) -> set[tuple[int, int]]:
    """Cells a player can work out instead of recognising.

    Two known cells on a run fix its step, and therefore its whole ramp; a
    known cell shared with another run hands that run a second anchor. So
    knowledge spreads exactly like a crossword. Everything this reaches can be
    computed; everything it misses has to be matched by eye.
    """
    known = set(known)
    changed = True
    while changed:
        changed = False
        for grad in shape.gradients:
            if sum(1 for cell in grad.cells if cell in known) >= 2:
                for cell in grad.cells:
                    if cell not in known:
                        known.add(cell)
                        changed = True
    return known


def rival_margins(shape, colors) -> dict[tuple[int, int], float]:
    """For each cell, how much closer its own colour is than the next nearest
    colour on the board. This is the gap a player's eye has to resolve when
    deduction cannot tell them which swatch goes here."""
    board: dict[tuple[int, int], OKLCh] = {}
    for gi, grad in enumerate(shape.gradients):
        for pos, cell in enumerate(grad.cells):
            board.setdefault(cell, colors[gi][pos])
    keys = sorted(board)
    out = {}
    for i, cell in enumerate(keys):
        rivals = [dist(board[cell], board[other])
                  for j, other in enumerate(keys) if j != i]
        out[cell] = min(rivals) if rivals else float("inf")
    return out


def unorientable_runs(shape, locked) -> list[int]:
    """Runs the player cannot lay down even with a perfect eye.

    A player solves by sorting, not by matching: group the swatches by which
    run they belong to (the runs are deliberately different colour families),
    order each group along its ramp (possible whenever consecutive steps beat
    the eye's noise), and then decide which way round the run goes. That last
    step needs an anchor. One given cell on the run settles it. So does a cell
    shared with a run that is already down, because the shared colour pins this
    run's position.

    A run with neither is floating: its swatches are sortable but its direction
    is a coin flip, and no amount of colour separation fixes that. The solver
    still calls such a board uniquely solvable, because exhaustive search over
    exact colours can rule the reversal out, but a person cannot run that
    search. This is the gap between "has one solution" and "can be solved".
    """
    oriented: set[int] = set()
    for gi, grad in enumerate(shape.gradients):
        if any(cell in locked for cell in grad.cells):
            oriented.add(gi)
    # Orientation spreads through crossings: once a run is down, the cell it
    # shares with a neighbour is known, and that anchors the neighbour.
    changed = True
    while changed:
        changed = False
        for gi, grad in enumerate(shape.gradients):
            if gi in oriented:
                continue
            for gj, other in enumerate(shape.gradients):
                if gj == gi or gj not in oriented:
                    continue
                if set(grad.cells) & set(other.cells):
                    oriented.add(gi)
                    changed = True
                    break
    return [gi for gi in range(len(shape.gradients)) if gi not in oriented]


def player_ambiguities(shape, colors, locked) -> list[str]:
    """Alternative arrangements a player has no way to rule out.

    A person can check exactly three things: the given cells are still where
    they started, every bank swatch got used, and every run reads as an even
    walk. They cannot check what the authored per-step deltas were, which is
    what `PuzzleSolver` compares against. So the solver will happily certify a
    board where some other arrangement satisfies all three of the player's
    checks, and that board is a coin flip in the hand.

    Two ways that happens, both found by simulated play:

    * **reversal**: a run laid down backwards is still an even walk. A given or
      shared cell only rules it out when it sits OFF centre, because reversing
      leaves the midpoint of an odd-length run exactly where it was. Symmetric
      shapes with a crossing in the middle (`cc+cc`) are the trap.
    * **swap**: two cells on different runs exchange colours and both runs stay
      even walks. Nothing on screen distinguishes that from the intended
      answer.
    """
    problems: list[str] = []

    shared = {cell for cell in shape.all_cells
              if sum(1 for g in shape.gradients if cell in g.cells) > 1}

    def walks_evenly(run_cells, values) -> bool:
        """Does this sequence read as one even walk?

        Build the steps eagerly. A generator expression here captures the
        comprehension's loop variable by reference, so materialising it later
        gives every step the LAST step's value, every run looks perfectly even,
        and the check reports every swap on the board as undetectable. That bug
        made this claim 94 levels out of 100 when the truth was 10.
        """
        if len(values) < 3:
            return True
        labs = [to_lab(v) for v in values]
        first = tuple(labs[1][k] - labs[0][k] for k in range(3))
        for i in range(1, len(values) - 1):
            step = tuple(labs[i + 1][k] - labs[i][k] for k in range(3))
            gap = math.sqrt(sum(((step[k] - first[k]) * 100) ** 2 for k in range(3)))
            if gap >= 2:
                return False
        return True

    # Lay the whole board out, so a reversal can be judged by its effect on
    # every run rather than on the reversed one alone.
    board_now: dict[tuple[int, int], OKLCh] = {}
    for gi, grad in enumerate(shape.gradients):
        for pos, cell in enumerate(grad.cells):
            board_now.setdefault(cell, colors[gi][pos])

    for gi, grad in enumerate(shape.gradients):
        cols = colors[gi]
        n = len(cols)
        if n < 2 or dist(cols[0], cols[-1]) < 2:
            continue
        # Reversing moves each cell's colour to its mirror position. Check the
        # consequence on the whole board: a given cell must not move, and every
        # run, including the ones that only share a cell with this one, must
        # still read as an even walk. Judging the reversed run in isolation and
        # treating its shared cells as fixed misses the case where a crossing
        # partner is happy to absorb the change.
        after = dict(board_now)
        for j, cell in enumerate(grad.cells):
            after[cell] = cols[n - 1 - j]
        moved = [cell for cell in grad.cells
                 if dist(after[cell], board_now[cell]) >= 2]
        if not moved:
            continue                          # a palindrome, caught elsewhere
        if any(cell in locked for cell in moved):
            continue                          # a given cell would have to move
        touched = [g for g in shape.gradients
                   if any(cell in g.cells for cell in moved)]
        if all(walks_evenly(g.cells, [after[c] for c in g.cells]) for g in touched):
            problems.append(f"run {gi} reads the same reversed")

    # Swaps: only free cells can move, and a swap has to leave every run it
    # touches still walking evenly.
    board: dict[tuple[int, int], OKLCh] = {}
    for gi, grad in enumerate(shape.gradients):
        for pos, cell in enumerate(grad.cells):
            board.setdefault(cell, colors[gi][pos])
    free = [cell for cell in sorted(shape.all_cells) if cell not in locked]

    # Players do read step scale, so an alternative that leaves one run
    # striding twice as far as everything else around it is not actually
    # confusing: it looks wrong. Only count a swap that keeps every run it
    # touches walking at a rate the rest of the board makes plausible. Without
    # this the check condemns every pair of two-cell runs, since any two
    # colours are trivially an even walk, and no given cell can ever fix that.
    run_steps = []
    for gi, grad in enumerate(shape.gradients):
        cols = colors[gi]
        if len(cols) >= 2:
            run_steps.append(sum(dist(cols[i], cols[i + 1])
                                 for i in range(len(cols) - 1)) / (len(cols) - 1))
    typical = statistics.median(run_steps) if run_steps else 0.0

    def plausible_pace(values) -> bool:
        if len(values) < 2:
            return True
        pace = sum(dist(values[i], values[i + 1])
                   for i in range(len(values) - 1)) / (len(values) - 1)
        return typical / 1.8 <= pace <= typical * 1.8

    for i in range(len(free)):
        for j in range(i + 1, len(free)):
            a, b = free[i], free[j]
            if dist(board[a], board[b]) < 2:
                continue                      # same colour, swapping is a no-op
            swapped = dict(board)
            swapped[a], swapped[b] = board[b], board[a]
            touched = [g for g in shape.gradients if a in g.cells or b in g.cells]
            values = {id(g): [swapped[c] for c in g.cells] for g in touched}
            if all(walks_evenly(g.cells, values[id(g)]) and plausible_pace(values[id(g)])
                   for g in touched):
                problems.append(f"cells {a} and {b} can swap unnoticed")
    return problems


def eye_only_problems(shape, colors, locked, floor) -> list[tuple[int, int]]:
    """Cells the player must judge purely by eye, at a gap under `floor`.

    A tight call is fair when structure forces the answer, because then the
    player computes it and never has to trust their eye. The same tightness on
    a cell deduction cannot reach is a coin flip, and thirty of those in a row
    is a lottery rather than a puzzle. So this is the check that decides
    whether a board is playable by a person, separately from whether it has
    exactly one solution.
    """
    margins = rival_margins(shape, colors)
    reachable = deduction_closure(shape, locked)
    return [cell for cell in sorted(shape.all_cells)
            if cell not in locked and cell not in reachable
            and margins[cell] < floor]


def choose_locks(shape, colors, cfg, rng) -> set[tuple[int, int]] | None:
    """Reveal starter cells: endpoints first, then spread inward until the
    bank is near target, then whatever deduction and uniqueness demand."""
    all_cells = sorted(shape.all_cells)
    locked: set[tuple[int, int]] = set()

    # Endpoints anchor a gradient's direction, which is the single most
    # useful thing to hand a new player.
    endpoints = []
    for g in shape.gradients:
        endpoints.append(g.cells[0])
        endpoints.append(g.cells[-1])
    seen = set()
    endpoints = [e for e in endpoints if not (e in seen or seen.add(e))]

    target_bank = max(1, cfg["bank_target"])

    def bank_size(locks):
        return len(all_cells) - len(locks)

    for cell in endpoints:
        if bank_size(locked) <= target_bank:
            break
        trial = locked | {cell}
        if every_gradient_free(shape, trial):
            locked = trial

    # Still too generous a bank? Reveal interior cells, evenly spaced.
    if bank_size(locked) > target_bank:
        interior = [c for c in all_cells if c not in locked]
        rng.shuffle(interior)
        for cell in interior:
            if bank_size(locked) <= target_bank:
                break
            trial = locked | {cell}
            if every_gradient_free(shape, trial):
                locked = trial

    # Now make the board solvable by a person, not just by a search. Every run
    # needs an anchor so its direction is settleable: a given cell of its own,
    # or a crossing that inherits one. Seed the floating runs, cheapest first,
    # and prefer an endpoint because an end pins direction with one cell.
    for _ in range(len(shape.gradients) + 1):
        floating = unorientable_runs(shape, locked)
        if not floating:
            break
        best, best_gain = None, -1
        for gi in floating:
            grad = shape.gradients[gi]
            # Endpoints first, then inward: an endpoint settles direction on
            # its own, an interior cell only does so together with the ramp.
            ordered = [grad.cells[0], grad.cells[-1]] + list(grad.cells[1:-1])
            for cell in ordered:
                if cell in locked:
                    continue
                trial = locked | {cell}
                if not every_gradient_free(shape, trial):
                    continue
                # One lock can rescue several runs at once when it lands on a
                # chain of crossings, so score by how many runs it orients.
                gain = len(floating) - len(unorientable_runs(shape, trial))
                if gain > best_gain:
                    best, best_gain = cell, gain
        if best is None:
            break
        locked = locked | {best}

    # If some run still cannot be oriented, this shape and lock budget cannot
    # produce a fair board: every gradient has to keep a free cell, so a
    # two-cell run whose only other cell is needed elsewhere can strand. Let
    # the search try again rather than shipping a coin flip.
    if unorientable_runs(shape, locked):
        return None

    # Now the stronger demand: no arrangement the player cannot rule out. A
    # centred crossing anchors a run's position but not its direction, and two
    # cells on different runs can sometimes trade places with both runs still
    # walking evenly. Give away whichever cell kills the most of those.
    # Now the demand the solver cannot make: no arrangement the player is
    # unable to rule out. A run whose only anchor sits at its midpoint can be
    # laid down backwards, and two cells can sometimes trade places with both
    # their runs still walking evenly. One given cell kills either, so the
    # budget is small; if a palette needs more than that, it is the colours
    # that are wrong and the search should try again rather than buy fairness
    # by giving the board away.
    ambiguity_budget = max(2, len(all_cells) // 8)
    for _ in range(ambiguity_budget):
        ambiguities = player_ambiguities(shape, colors, locked)
        if not ambiguities:
            break
        best, best_gain = None, 0
        for cell in all_cells:
            if cell in locked:
                continue
            trial = locked | {cell}
            if not every_gradient_free(shape, trial):
                continue
            gain = len(ambiguities) - len(player_ambiguities(shape, colors, trial))
            if gain > best_gain:
                best, best_gain = cell, gain
        if best is None:
            return None
        locked = locked | {best}
    if player_ambiguities(shape, colors, locked):
        return None

    # Uniqueness. Lock cells the solver says are interchangeable until
    # exactly one arrangement survives.
    for _ in range(60):
        puz = build_puzzle(shape, colors, locked)
        found = placements(puz, limit=2)
        if len(found) <= 1:
            return locked
        a, b = found[0], found[1]
        diff = [cell for cell in a if dist(a[cell], b[cell]) >= 2]
        diff.sort()
        placed = False
        for cell in diff:
            trial = locked | {cell}
            if every_gradient_free(shape, trial):
                locked = trial
                placed = True
                break
        if not placed:
            return None
    return None


# ─── Tip claims ────────────────────────────────────────────────────

def circular_mean(hues) -> float:
    x = sum(math.cos(math.radians(h)) for h in hues)
    y = sum(math.sin(math.radians(h)) for h in hues)
    return math.degrees(math.atan2(y, x)) % 360


def hue_gap(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def unmet_claims(shape, colors, locked, name) -> list[str]:
    """Which of this level's tip claims the board fails (see TIP_CLAIMS)."""
    claims = shapes.TIP_CLAIMS.get(name, set())
    if not claims:
        return []
    cells = shape.all_cells
    crossings = len(shape.cross_cells)
    failed = []

    for claim in sorted(claims):
        if claim == "ends-locked":
            ok = all(g.cells[0] in locked and g.cells[-1] in locked
                     for g in shape.gradients)
        elif claim == "bank1":
            ok = len(cells) - len(locked) == 1
        elif claim == "crossing":
            ok = crossings >= 1
        elif claim == "crossing4":
            ok = crossings == 4
        elif claim == "no-crossing":
            ok = crossings == 0
        elif claim == "all-crossed":
            ok = all(any(cell in shape.cross_cells for cell in g.cells)
                     for g in shape.gradients)
        elif claim == "families":
            means = [circular_mean([c.h for c in cols]) for cols in colors]
            ok = all(hue_gap(means[i], means[j]) >= 45
                     for i in range(len(means))
                     for j in range(i + 1, len(means)))
        elif claim == "chroma-ramp":
            # A gradient whose chroma moves while its hue stays put — which
            # is what "same hue, draining colour" describes.
            ok = any(
                abs(cols[1].c - cols[0].c) > 0.008
                and hue_gap(cols[0].h, cols[1].h) < 2
                for cols in colors if len(cols) >= 2
            )
        elif claim == "equal-lengths":
            lengths = {len(g.cells) for g in shape.gradients}
            ok = len(lengths) == 1
        elif claim == "grid-9-rows":
            ok = shape.grid_h == 9
        else:
            raise ValueError(f"{name}: unknown tip claim {claim!r}")
        if not ok:
            failed.append(claim)
    return failed


# ─── Difficulty target ─────────────────────────────────────────────

# How hard each level is *meant* to be, as the number of cells a typical eye
# leaves wrong on a first pass, ramping inside each chapter and resetting a
# little lower at each chapter opening. Same sawtooth the bank curve draws,
# stated in the units a player actually experiences.
#
# Wrong cells rather than boards-solved, for two reasons. It is what a campaign
# level costs the player: these boards auto-solve with no Check and no hearts,
# so a first pass that is not right is a hunt back through what you placed, and
# its length is the difficulty. And it is a mean rather than a proportion, so 40
# trials pin it to a few hundredths where the same trials leave a success rate
# swinging ten points, which matters when the number is being used to choose
# between candidates.
BOOK2_DIFFICULTY = {
    "Workshop":    (1.2, 2.4),
    "Orchestra":   (1.6, 2.8),
    "Circuitry":   (2.0, 3.2),
    "Interiors":   (2.4, 3.6),
    "Grand Works": (2.8, 4.0),
}

# How far the search may move a level's bank size off its chapter's, how many
# palettes to weigh at each of those sizes, the band inside which a board is
# near enough to stop looking, and the trials each measurement runs.
BANK_WINDOW = 8
TUNE_PALETTES = 3
TUNE_TOLERANCE = 0.35
TUNE_TRIALS = 40
# The noise-free gate needs only a few, since the only randomness left at zero
# noise is which way a genuine tie falls.
CONTROL_TRIALS = 4


def difficulty_target(level: int) -> float | None:
    """Wrong-cell target for this level, or None where none is set."""
    title, first, last, _blurb = shapes.chapter_of(level)
    band = BOOK2_DIFFICULTY.get(title)
    if band is None:
        return None
    return lerp(band[0], band[1], (level - first) / max(1, last - first))


def measure_difficulty(entry: dict) -> tuple[bool, float]:
    """(a perfect eye lands it, cells a typical eye leaves wrong).

    Both conditions, because the second one alone would happily call a board
    that nobody can finish "appropriately hard". A board the noise-free solver
    cannot land is not a difficulty, it is a defect, whether that is a genuine
    ambiguity or one of the reasoning player's documented blind spots, and
    either way it is not what a level should be selected for.

    Imported lazily: `playtest` is a heavy module and every level that is not
    being tuned should not pay to import it.
    """
    import playtest
    level = playtest._level_from_entry(entry)
    control = playtest.Settings("noise-free control", sigma=0.0, k=0.0, t=0.0,
                                misclick=0.0)
    if playtest.run_level(level, control, CONTROL_TRIALS, "reason").success < 1.0:
        return False, 0.0
    typical = playtest.Settings("typical eye", sigma=2.0, k=0.0, t=1.5,
                                misclick=0.0)
    return True, playtest.run_level(level, typical, TUNE_TRIALS,
                                    "reason").mean_wrong


# ─── Level assembly ────────────────────────────────────────────────

def build_level(level: int, name: str, artwork: str, tip: str | None,
                verbose: bool = False) -> dict:
    shape = art.parse(artwork, name)
    cfg = curve(level)
    FAILS.clear()          # so the failure report below describes THIS level
    target = difficulty_target(level)

    if target is None:
        for entry in valid_entries(level, shape, name, tip, cfg):
            if verbose:
                print(f"  level {level:3d} {name:12s} {shape.grid_w}x{shape.grid_h} "
                      f"grads={entry['gradientCount']} cells={entry['cellCount']} "
                      f"bank={entry['bankCount']} "
                      f"minDE={entry['minPairDeltaE']:.1f} "
                      f"tries={entry['attempts']}")
            return entry
        raise _no_palette(level, name)

    # Everything `valid_entries` yields is a legal board. Nothing about it says
    # how hard the board turned out, and that varies a long way between boards
    # that are equally legal. Pliers and Level are neighbours built to the same
    # bank size and read at 8% and 68% to a typical eye, a spread far louder
    # than the curve it sits on, so a level lands wherever its first valid
    # palette happened to fall.
    #
    # So search instead of settling: walk outward from the chapter's bank size,
    # weigh a few palettes at each, and keep whichever board comes nearest the
    # level's difficulty target. Bank size is searched because it is the knob
    # that actually moves difficulty, and the window keeps the chapter's ramp
    # in charge of the shape of the curve while letting a level that is far off
    # it be pulled back. Selection only ever swaps one already-valid board for
    # another, so it cannot invent an unfair one, and it pulls toward the middle
    # of the distribution rather than exploiting its ends, which is the honest
    # way to use a simulated player whose ordering is trustworthy but whose
    # absolute numbers are asserted.
    def weigh(bank: int) -> tuple[float, dict, float] | None:
        """Nearest-to-target board at this bank size, over a few palettes."""
        local = None
        weighed = examined = 0
        for entry in valid_entries(level, shape, name, tip,
                                   dict(cfg, bank_target=bank)):
            examined += 1
            if examined > TUNE_PALETTES * 4:
                break        # this size keeps failing the gate; move on
            landed, wrong = measure_difficulty(entry)
            if not landed:
                if verbose:
                    print(f"    bank {bank:2d}: a perfect eye misses this board")
                continue
            entry["typicalWrong"] = round(wrong, 2)
            miss = abs(wrong - target)
            if local is None or miss < local[0]:
                local = (miss, entry, wrong)
            weighed += 1
            if verbose:
                print(f"    bank {bank:2d} palette {weighed}: wrong {wrong:5.2f} "
                      f"vs target {target:.2f}")
            if weighed >= TUNE_PALETTES:
                break
        return local

    # Walk rather than scan: one swatch fewer is always one decision fewer, so
    # difficulty is monotone in bank size and the direction to move is known
    # from the sign of the miss. The walk stops when it lands inside the
    # tolerance, when it steps outside the window, or when it turns back onto a
    # size it has already weighed, which means the target sits between two
    # neighbouring bank sizes and no third one will do better.
    base = cfg["bank_target"]
    cells = len(shape.all_cells)
    low, high = max(1, base - BANK_WINDOW), min(cells - 1, base + BANK_WINDOW)
    bank = min(max(base, low), high)
    best: tuple[float, dict, float] | None = None   # (miss, entry, wrong)
    seen: set[int] = set()
    while bank not in seen:
        seen.add(bank)
        local = weigh(bank)
        if local is None:
            break            # no legal board at this size; keep what we have
        if best is None or local[0] < best[0]:
            best = local
        if local[0] <= TUNE_TOLERANCE:
            break
        step = -1 if local[2] > target else 1     # too hard, give a cell back
        if not low <= bank + step <= high:
            break
        bank += step

    if best is None:
        raise _no_palette(level, name)
    entry = best[1]
    if verbose:
        print(f"  level {level:3d} {name:12s} {shape.grid_w}x{shape.grid_h} "
              f"grads={entry['gradientCount']} cells={entry['cellCount']} "
              f"bank={entry['bankCount']} minDE={entry['minPairDeltaE']:.1f} "
              f"wrong={entry['typicalWrong']:.2f} target={target:.2f}")
    return entry


def _no_palette(level: int, name: str) -> RuntimeError:
    claim_fails = {k: v for k, v in FAILS.items() if k.startswith("tip_claim:")}
    return RuntimeError(
        f"level {level} ({name}): no valid palette"
        + (f" — tip claims blocking it: {claim_fails}" if claim_fails else ""))


def valid_entries(level: int, shape, name: str, tip: str | None, cfg: dict,
                  budget: int = 4000):
    """Yield every board for this level that clears every rule, in seed order.

    Split out of `build_level` so the same search can be run more than once
    with a different bank size. The attempt index seeds both the palette and
    the relax ramp, so a given attempt paints identically whatever bank it is
    asked for, and only the given cells move between runs.
    """
    for attempt in range(budget):
        attempts = attempt + 1
        rng = random.Random(level * 7919 + attempt)
        relax = 1.0 - min(0.45, attempt / 3000.0)
        scaled = dict(cfg)
        scaled["de_floor"] = max(5.2, cfg["de_floor"] * relax)
        scaled["step_floor"] = max(4.2, cfg["step_floor"] * relax)
        # The partition demand is a preference, not a floor: Reactor showed that
        # a dense shape can fail every painting attempt under it. Walk it down
        # so such a shape still ships, and record what it actually got.
        #
        # Book two only. Landmarks already pays the full 0.9 on every level, and
        # letting it decay there re-solved Castle, Temple and Garden against a
        # weaker rule than they had shipped under (Castle's closest pair fell
        # from 6.11 to 5.45 delta-E). Giving ground is for boards that have not
        # already proved they can hold it.
        if level > COLOUR_CURVE_END:
            scaled["sep_ratio"] = max(0.0, cfg["sep_ratio"] - attempt / 1500.0)
        colors = paint(shape, scaled, rng)
        if colors is None:
            continue
        locked = choose_locks(shape, colors, scaled, rng)
        if locked is None:
            continue
        # The level's tip describes this board, so a palette that makes the
        # tip false is not a usable palette.
        missing = unmet_claims(shape, colors, locked, name)
        if missing:
            _fail("tip_claim:" + ",".join(missing))
            continue
        puz = build_puzzle(shape, colors, locked)
        if count_placements(puz, limit=2) != 1:
            continue
        board = {}
        for gi, grad in enumerate(shape.gradients):
            for pos, cell in enumerate(grad.cells):
                board.setdefault(cell, colors[gi][pos])
        min_pair = min(
            dist(board[a], board[b])
            for i, a in enumerate(sorted(board))
            for b in sorted(board)[i + 1:]
        ) if len(board) > 1 else 99.0
        doc = {
            "version": 1,
            "gridW": shape.grid_w,
            "gridH": shape.grid_h,
            "name": name,
            "gradients": [
                {
                    "dir": g.direction,
                    "cells": [
                        {
                            "r": r, "c": c,
                            "L": round(colors[gi][pos].L, 5),
                            "C": round(colors[gi][pos].c, 5),
                            "h": round(norm_h(colors[gi][pos].h), 3),
                            "locked": (r, c) in locked,
                        }
                        for pos, (r, c) in enumerate(g.cells)
                    ],
                }
                for gi, g in enumerate(shape.gradients)
            ],
        }
        chapter = shapes.chapter_of(level)
        entry = {
            "index": level,
            "name": name,
            "chapter": chapter[0],
            "tip": tip,
            "gradientCount": len(shape.gradients),
            "cellCount": len(board),
            "bankCount": len(board) - len(locked),
            "minPairDeltaE": round(min_pair, 2),
            "attempts": attempts,
            "doc": doc,
        }
        # Book two only, so the first hundred's JSON keys stay exactly as they
        # shipped and a rebuild diff still proves the curve clamp changed
        # nothing there. This records what the partition demand actually got,
        # which matters because it is allowed to give ground.
        if level > COLOUR_CURVE_END:
            entry["sepRatio"] = round(scaled["sep_ratio"], 3)
        yield entry


def check_teaching_order(levels: list[dict]) -> list[str]:
    """A mechanic must not show up before the tip that introduces it.

    The tips are written as a sequence ("two gradients now", "chroma ramps
    now too"), so if the difficulty curve starts using a channel or a shared
    cell earlier than its tip, the campaign teaches out of order.
    """
    problems = []

    def first_where(predicate) -> int | None:
        for entry in levels:
            if predicate(entry):
                return entry["index"]
        return None

    def has_chroma_ramp(entry) -> bool:
        for grad in entry["doc"]["gradients"]:
            cells = grad["cells"]
            if len(cells) < 2:
                continue
            d_c = abs(cells[1]["C"] - cells[0]["C"])
            d_h = abs((cells[1]["h"] - cells[0]["h"] + 180) % 360 - 180)
            if d_c > 0.008 and d_h < 2:
                return True
        return False

    def tip_mentions(entry, word) -> bool:
        return bool(entry["tip"]) and word in entry["tip"].lower()

    # (what to look for, the word whose tip introduces it)
    for finder, word, label in [
        (has_chroma_ramp, "chroma", "a chroma ramp"),
        (lambda e: len(e["doc"]["gradients"]) >= 2, "two gradients", "a second gradient"),
    ]:
        introduced = first_where(lambda e: tip_mentions(e, word))
        appears = first_where(finder)
        if introduced is not None and appears is not None and appears < introduced:
            problems.append(
                f"{label} first appears on level {appears}, but the tip that "
                f"introduces it is on level {introduced}")
    return problems


def _build_one(task):
    """Worker entry point: one level, start to finish.

    Top level rather than a closure so it can be pickled to a subprocess.
    """
    index, name, artwork, tip = task
    return build_level(index, name, artwork, tip, verbose=False)


def build_all(verbose=True, workers=None) -> dict:
    """Build the whole campaign, in parallel by default.

    Levels are independent: each one's palette search is seeded from its own
    index and attempt number, and nothing carries over between them. The
    module-level caches (`FAILS`, `_CHROMA_CAP`) are per process, and one is a
    counter and the other a pure memo of the sRGB chroma ceiling, so a worker
    having its own copy changes no result. That independence is what makes the
    output byte-identical whether this runs on one core or twelve, which is
    worth preserving: a campaign that reshuffled itself per machine would make
    every rebuild an unreviewable diff.

    Scheduling is dynamic because the work is wildly uneven. Most levels land
    in a handful of attempts, while the constrained shapes (Reactor, Palace,
    Carousel) can take hundreds, so handing out fixed chunks would leave most
    cores idle waiting for one straggler.
    """
    tasks = [(i, name, artwork, tip)
             for i, (name, artwork, tip) in enumerate(shapes.ALL, start=1)]
    levels: list[dict | None] = [None] * len(tasks)
    workers = workers or os.cpu_count() or 1

    if workers <= 1:
        for task in tasks:
            entry = _build_one(task)
            levels[task[0] - 1] = entry
            if verbose:
                print(f"  level {entry['index']:3d} {entry['name']:12} "
                      f"bank={entry['bankCount']:2d} tries={entry['attempts']}")
    else:
        done = 0
        with ProcessPoolExecutor(max_workers=workers) as pool:
            pending = {pool.submit(_build_one, task): task[0] for task in tasks}
            for future in as_completed(pending):
                # A level that cannot be built raises here, carrying its own
                # name and blocker counts from build_level.
                entry = future.result()
                levels[entry["index"] - 1] = entry
                done += 1
                if verbose:
                    print(f"  [{done:3d}/{len(tasks)}] level {entry['index']:3d} "
                          f"{entry['name']:12} bank={entry['bankCount']:2d} "
                          f"tries={entry['attempts']}", flush=True)
    levels = [entry for entry in levels if entry is not None]
    order_problems = check_teaching_order(levels)
    if order_problems:
        raise RuntimeError("teaching order is wrong:\n  "
                           + "\n  ".join(order_problems))
    return {
        "version": 1,
        "chapters": [
            {"title": t, "first": f, "last": l, "blurb": b}
            for (t, f, l, b) in shapes.CHAPTERS
        ],
        "levels": levels,
    }


# ─── Contact sheet ─────────────────────────────────────────────────

def render_sheet(campaign: dict, path: Path, cols: int = 10, cell: int = 14):
    from PIL import Image, ImageDraw

    pad, label_h = 10, 16
    tile_w = 11 * cell + pad * 2
    tile_h = 9 * cell + pad + label_h
    rows = (len(campaign["levels"]) + cols - 1) // cols
    img = Image.new("RGB", (cols * tile_w, rows * tile_h), (18, 18, 20))
    draw = ImageDraw.Draw(img)
    for i, lv in enumerate(campaign["levels"]):
        ox = (i % cols) * tile_w
        oy = (i // cols) * tile_h
        doc = lv["doc"]
        board = {}
        for g in doc["gradients"]:
            for c in g["cells"]:
                board[(c["r"], c["c"])] = c
        gw, gh = doc["gridW"], doc["gridH"]
        x0 = ox + pad + (11 - gw) * cell // 2
        y0 = oy + label_h + (9 - gh) * cell // 2
        for (r, c), spec in board.items():
            rgb = to_srgb8(OKLCh(spec["L"], spec["C"], spec["h"]))
            x, y = x0 + c * cell, y0 + r * cell
            draw.rectangle([x, y, x + cell - 2, y + cell - 2], fill=rgb)
            if spec.get("locked"):
                draw.rectangle([x, y, x + cell - 2, y + cell - 2],
                               outline=(255, 255, 255), width=1)
        draw.text((ox + 4, oy + 3), f"{lv['index']} {lv['name']}", fill=(210, 210, 215))
    img.save(path)
    return path


def _display_path(path: Path) -> str:
    """Repo-relative when it is inside the repo, absolute otherwise, so an
    --out somewhere else does not blow up the summary line."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true", help="render the review PNG")
    ap.add_argument("--level", type=int, help="build a single level and print it")
    ap.add_argument("--out", type=Path, default=OUT_JSON)
    ap.add_argument("--workers", type=int, default=None,
                    help="parallel level builders (default: one per core, 1 to debug)")
    args = ap.parse_args()

    if args.level:
        name, artwork, tip = shapes.ALL[args.level - 1]
        entry = build_level(args.level, name, artwork, tip, verbose=True)
        print(json.dumps({k: v for k, v in entry.items() if k != "doc"}, indent=2))
        return 0

    campaign = build_all(workers=args.workers)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(campaign, separators=(",", ":")))
    total_bank = sum(l["bankCount"] for l in campaign["levels"])
    print(f"wrote {_display_path(args.out)} — {len(campaign['levels'])} levels, "
          f"{total_bank} swatches to place, "
          f"{args.out.stat().st_size // 1024} KB")
    if args.sheet:
        print("sheet:", render_sheet(campaign, OUT_SHEET))
    return 0


if __name__ == "__main__":
    sys.exit(main())
