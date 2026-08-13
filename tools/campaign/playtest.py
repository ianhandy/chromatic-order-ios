"""Monte Carlo playtest of the authored campaign with an imperfect solver.

The uniqueness solver (`solver.py`) answers "is the authored arrangement the
only one that looks like itself". That is the wrong question for difficulty
tuning, because it gates candidate swatches on the authored colour of each cell,
so it can only ever rediscover the answer. This module asks the other question:
how often does a *person* land the level, given that a person sees colours
through noise, cannot separate near-identical swatches at all, fumbles the
occasional drag, and reasons from what is on the board rather than from the
answer key.

Two strategies are modelled, selected with --strategy:

  * `reason` (default) plays the way people describe playing. Partition the bank
    into runs, order each run along its line, resolve which way round the run
    goes, and use deduction wherever two known cells pin a ramp outright.
  * `match` is the careless player: walk the board cell by cell, always drop in
    the swatch nearest to what you extrapolate. Kept for comparison, because the
    gap between the two is the value of playing carefully.

Alongside the simulation, four analytic numbers per level, none of which need a
single trial:

  * between-run separation: the closest approach of two different runs' colours,
    which is what the partition step can fail on.
  * within-run step: the smallest step along any run, which is what the ordering
    step can fail on.
  * unpinned runs: runs whose direction no given cell fixes, even following
    chains of crossings. A run with no anchor is a coin flip for anybody.
  * hardest bank margin: the closest pair of bank swatches, the original
    single-number difficulty proxy, kept so the four can be compared.

    python3 playtest.py                        # default sweep, writes csv + md
    python3 playtest.py --level 90             # one level, decision by decision
    python3 playtest.py --strategy match       # the careless player
    python3 playtest.py --trials 500 --sigma 2.5

Pure standard library plus the sibling `oklch` module, same as the rest of the
authoring toolchain.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
import math
import random
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

from oklch import OKLCh, dist, lab_dist, to_lab

HERE = Path(__file__).resolve().parent
CAMPAIGN = HERE.parents[1] / "ChromaticOrder" / "Resources" / "campaign.json"

# Stand-in for "no rival exists", matching the sentinel build.py uses for
# minPairDeltaE on single-swatch boards. Kept finite so it sorts and averages.
NO_RIVAL = 99.0

# The app judges a placement correct when the placed colour is within this
# delta-E of the cell's authored colour (TestingFilter.sameThreshold, default 2,
# which is OK.equal's own JND cutoff). Every authored level keeps its bank pairs
# at least delta-E 4 apart, so "the right swatch" and "a swatch that reads as the
# right one" are the same thing here, and counting wrong cells by identity
# matches what the game would score.
SAME = 2.0


# ---------------------------------------------------------------------------
# Level model
# ---------------------------------------------------------------------------
#
# A board is stored per gradient in the JSON, and a crossing appears twice (once
# in each gradient's cell list) with identical colour and identical locked flag
# (verified across all 100 levels: zero mismatches). So the board is really a
# flat set of unique cells, plus gradients expressed as index paths into it.
# Flattening early is what makes information propagate across a crossing for
# free: filling a shared cell marks it known in both runs at once, with no
# special case anywhere in the player loop.


@dataclass
class Level:
    index: int
    name: str
    chapter: str
    grid_w: int
    grid_h: int
    cells: list[tuple[int, int]]              # unique (r, c), stable order
    truth: list[OKLCh]                        # authored colour per cell
    truth_lab: list[tuple[float, float, float]]
    locked: list[bool]
    gradients: list[list[int]]                # cell indices, in run order
    bank: list[int]                           # cell indices that start empty
    neighbours: list[list[int]]               # 4-way grid adjacency, cell indices
    tips: list[int] = field(default_factory=list)      # uncrossed run ends
    run_ends: list[int] = field(default_factory=list)  # every run end
    # Analytic difficulty, all computed once from the authored colours.
    margin: float = NO_RIVAL                  # closest bank pair
    margin_pair: tuple[int, int] | None = None
    rival: list[float] = field(default_factory=list)   # per bank cell
    run_sep: float = NO_RIVAL                 # closest approach of two runs
    run_sep_pair: tuple[int, int] | None = None
    min_step: float = NO_RIVAL                # smallest step along any run
    unpinned: list[int] = field(default_factory=list)  # runs with no anchor
    alt: str | None = None                    # proof of a second valid board

    @property
    def cell_count(self) -> int:
        return len(self.cells)


def load_levels(path: Path) -> list[Level]:
    doc = json.loads(path.read_text())
    return [_level_from_entry(entry) for entry in doc["levels"]]


def _level_from_entry(entry: dict) -> Level:
    index_of: dict[tuple[int, int], int] = {}
    cells: list[tuple[int, int]] = []
    truth: list[OKLCh] = []
    locked: list[bool] = []
    gradients: list[list[int]] = []

    for grad in entry["doc"]["gradients"]:
        path: list[int] = []
        for cell in grad["cells"]:
            key = (cell["r"], cell["c"])
            i = index_of.get(key)
            if i is None:
                i = len(cells)
                index_of[key] = i
                cells.append(key)
                truth.append(OKLCh(cell["L"], cell["C"], cell["h"]))
                locked.append(bool(cell["locked"]))
            path.append(i)
        gradients.append(path)

    # Grid adjacency is only used to make a misclick land somewhere plausible: a
    # slipped drag goes to a cell the thumb was already near, not to a random
    # corner of the board.
    neighbours: list[list[int]] = []
    for (r, c) in cells:
        near = []
        for (dr, dc) in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            j = index_of.get((r + dr, c + dc))
            if j is not None:
                near.append(j)
        neighbours.append(near)

    level = Level(
        index=entry["index"],
        name=entry["name"],
        chapter=entry["chapter"],
        grid_w=entry["doc"]["gridW"],
        grid_h=entry["doc"]["gridH"],
        cells=cells,
        truth=truth,
        truth_lab=[to_lab(col) for col in truth],
        locked=locked,
        gradients=gradients,
        bank=[i for i in range(len(cells)) if not locked[i]],
        neighbours=neighbours,
    )
    _mark_ends(level)
    _measure_margins(level)
    _measure_channels(level)
    _measure_orientation(level)
    level.alt = _alternative_arrangement(level)
    return level


def _mark_ends(level: Level) -> None:
    """Run ends, and the subset of them no second run passes through."""
    membership: dict[int, int] = {}
    ends: list[int] = []
    for path in level.gradients:
        for i in path:
            membership[i] = membership.get(i, 0) + 1
        for i in (path[0], path[-1]):
            if i not in ends:
                ends.append(i)
    level.run_ends = ends
    level.tips = [i for i in ends if membership[i] == 1]


def _measure_margins(level: Level) -> None:
    """Closest pair inside the bank: the hardest raw discrimination.

    For every empty cell the player must eventually separate its correct swatch
    from every other swatch still in the bank, so the tightest of those
    separations bounds the level. Locked cells are excluded on purpose: a locked
    colour sitting close to a bank swatch costs the player nothing, since a
    locked cell is never a drop target. That is where this differs from the
    authored `minPairDeltaE`, which measures the whole board.
    """
    bank = level.bank
    level.rival = [NO_RIVAL] * len(bank)
    if len(bank) < 2:
        level.margin = NO_RIVAL
        return
    best, best_pair = NO_RIVAL, None
    for a in range(len(bank)):
        near = NO_RIVAL
        for b in range(len(bank)):
            if a == b:
                continue
            d = dist(level.truth[bank[a]], level.truth[bank[b]])
            near = min(near, d)
            if d < best:
                best, best_pair = d, (bank[a], bank[b])
        level.rival[a] = near
    level.margin = best
    level.margin_pair = best_pair


def _measure_channels(level: Level) -> None:
    """The two perceptual channels a sorting player actually leans on.

    `run_sep` is how close two different runs' colours come to each other, which
    is what decides whether the bank can be partitioned by family at all. Cells
    shared by the two runs are excluded, since a crossing colour belongs to both
    runs by construction and is not a partition mistake waiting to happen.

    `min_step` is the smallest step along any run. Ordering a run means sorting
    its swatches along a line, and that only works while consecutive steps stay
    above the noise, so the smallest step anywhere on the board is the weakest
    link in the ordering channel.
    """
    grads = level.gradients
    sep, sep_pair = NO_RIVAL, None
    for gi in range(len(grads)):
        for gj in range(gi + 1, len(grads)):
            shared = set(grads[gi]) & set(grads[gj])
            for a in grads[gi]:
                if a in shared:
                    continue
                for b in grads[gj]:
                    if b in shared:
                        continue
                    d = dist(level.truth[a], level.truth[b])
                    if d < sep:
                        sep, sep_pair = d, (a, b)
    level.run_sep = sep
    level.run_sep_pair = sep_pair

    step = NO_RIVAL
    for path in grads:
        for a, b in zip(path, path[1:]):
            step = min(step, dist(level.truth[a], level.truth[b]))
    level.min_step = step


def _measure_orientation(level: Level) -> None:
    """Which runs have no given cell fixing which way round they go.

    Start from the deduction closure the app's own CampaignFairnessTests uses:
    a run holding two known cells gives up its whole ramp, which makes its
    crossings known, which can hand a second known cell to the runs they cross.
    Iterate to a fixpoint. Two known cells are the requirement and not one,
    because one known cell fixes no step: a two-cell run with its top given says
    nothing at all about the cell below it, since any two colours are an even
    walk.

    Then a run is anchored if the closure leaves it at least one known cell away
    from its exact centre. Anything less and the run reads identically forwards
    and backwards, so its direction is a coin flip unless something outside the
    run settles it. Those unanchored runs are the analytic twin of the `reason`
    strategy's orientation step.
    """
    grads = level.gradients
    known = set(i for i in range(len(level.cells)) if level.locked[i])
    changed = True
    while changed:
        changed = False
        for path in grads:
            if sum(1 for c in path if c in known) < 2:
                continue
            for c in path:
                if c not in known:
                    known.add(c)
                    changed = True

    level.unpinned = []
    for gi, path in enumerate(grads):
        n = len(path)
        if not any(c in known and p != n - 1 - p for p, c in enumerate(path)):
            level.unpinned.append(gi)


def _even_walk(level: Level, colour_at: dict[int, OKLCh],
               only: list[int] | None = None) -> bool:
    """Is every run in this arrangement an even walk, as a player would judge it?

    Evenness is checked in OKLCh, not OKLab, because that is where the generator
    walks and where the app's own solver says the walk lives (a pure-hue step
    projects to a curved arc in a/b, so equal Lab deltas is the wrong test). The
    test itself is the one a player can actually apply: interpolate between the
    two ends of the run and require every interior cell to sit within delta-E
    `SAME` of where the interpolation puts it.
    """
    for gi, path in enumerate(level.gradients):
        if only is not None and gi not in only:
            continue
        m = len(path)
        if m < 3:
            continue                      # any two colours are an even walk
        cols = [colour_at[c] for c in path]
        # Unwrap hue along the run so a ramp crossing 0 degrees is not read as a
        # near-full rotation.
        hs = [cols[0].h]
        for col in cols[1:]:
            h = col.h
            while h - hs[-1] > 180.0:
                h -= 360.0
            while h - hs[-1] < -180.0:
                h += 360.0
            hs.append(h)
        for i in range(1, m - 1):
            f = i / (m - 1)
            want = OKLCh(cols[0].L + f * (cols[-1].L - cols[0].L),
                         cols[0].c + f * (cols[-1].c - cols[0].c),
                         hs[0] + f * (hs[-1] - hs[0]))
            if dist(want, cols[i]) >= SAME:
                return False
    return True


def _step_oddity(level: Level, colour_at: dict[int, OKLCh]) -> float:
    """How far the most unusual run's step is from the board's median step.

    The player's other expectation, beyond each run being even, is that the runs
    on one board step at similar rates, because every board they have seen does
    (the median authored level's fastest run steps only 1.6x its slowest). So an
    arrangement that gives one run a step nothing like the rest reads as wrong
    even though every run is technically even. This measures that oddity, and
    the ambiguity proof only accepts an alternative that is no odder than the
    authored board itself.
    """
    steps = []
    for path in level.gradients:
        for a, b in zip(path, path[1:]):
            steps.append(dist(colour_at[a], colour_at[b]))
    if not steps:
        return 0.0
    mid = statistics.median(steps)
    return max(abs(s - mid) for s in steps)


def _alternative_arrangement(level: Level) -> str | None:
    """Try to construct a second arrangement a rule-following player cannot rule out.

    If one exists, the level is unfair by construction: two boards, both made of
    exactly the bank swatches, both keeping every given cell, both showing every
    run as an even walk, and visibly different from each other. No eyesight and
    no reasoning can choose between them, so the player is guessing and the app
    will call one of the guesses wrong.

    Two constructions are tried, both of which a player would hit naturally:

    * swapping two bank swatches. Undetectable whenever both cells sit only on
      runs that stay even afterwards, which is automatic for a run of two cells
      since any two colours are an even walk. A two-cell run with its other cell
      given therefore constrains nothing at all, and two of them on a board can
      always trade swatches.
    * reversing a run whose direction nothing pins, since reversing an even walk
      leaves it even.

    Returning None does not prove a level is fair, only that these two
    constructions found nothing.
    """
    base = {i: level.truth[i] for i in range(len(level.cells))}
    # A player has one more expectation beyond "each run is even": the runs on a
    # board step at similar rates, because that is what every board they have
    # seen looks like. An alternative that keeps every run even but gives one of
    # them a step three times the board's largest does not actually fool anyone,
    # so it is not counted as a proof. This is the difference between two legs of
    # a creature swapping colours (each leg would suddenly jump much further than
    # anything else on the board, so it reads as wrong) and two legs painted from
    # such similar families that the swap changes nothing anyone can see.
    ceiling = _step_oddity(level, base) * 1.25 + 0.5
    runs_of = {i: [gi for gi, path in enumerate(level.gradients) if i in path]
               for i in level.bank}
    for a in range(len(level.bank)):
        for b in range(a + 1, len(level.bank)):
            i, j = level.bank[a], level.bank[b]
            if dist(level.truth[i], level.truth[j]) < SAME:
                continue              # the swap would not be visible anyway
            trial = dict(base)
            trial[i], trial[j] = base[j], base[i]
            touched = sorted(set(runs_of[i]) | set(runs_of[j]))
            if _step_oddity(level, trial) > ceiling:
                continue
            if _even_walk(level, trial, only=touched):
                return (f"swap {level.cells[i]} with {level.cells[j]}: both sit "
                        "only on runs that stay even walks afterwards, and "
                        "neither run's step stands out")

    if not level.unpinned:
        return None
    trials: list[tuple[str, list[int]]] = [(f"run {gi}", [gi])
                                           for gi in level.unpinned]
    if len(level.unpinned) > 1:
        trials.append(("runs " + ",".join(str(g) for g in level.unpinned),
                       list(level.unpinned)))
    for label, runs in trials:
        trial = dict(base)
        for gi in runs:
            path = level.gradients[gi]
            for pos, cell in enumerate(path):
                trial[cell] = level.truth[path[len(path) - 1 - pos]]
        # A locked cell may not move, and the board must look different.
        if any(dist(trial[i], level.truth[i]) >= SAME
               for i in range(len(level.cells)) if level.locked[i]):
            continue
        if not any(dist(trial[i], level.truth[i]) >= SAME
                   for i in range(len(level.cells))):
            continue
        if _even_walk(level, trial):
            moved = [level.cells[i] for i in range(len(level.cells))
                     if dist(trial[i], level.truth[i]) >= SAME]
            return (f"{label} reversed: {len(moved)} cells change, "
                    f"first at {moved[0]}")
    return None


# ---------------------------------------------------------------------------
# The player's eye
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Settings:
    """One condition in the sweep. All four knobs model the eye, not the brain."""

    label: str
    sigma: float = 2.0      # total perceptual error per look, in delta-E units
    k: float = 0.0          # similarity compression applied to the board
    t: float = 1.5          # below this decision margin the player is guessing
    misclick: float = 0.0   # chance a drag lands in the wrong empty cell

    def describe(self) -> str:
        return (f"sigma={self.sigma:g} k={self.k:g} "
                f"t={self.t:g} misclick={self.misclick:g}")


# Human colour misjudgement is not pure flicker. Part of it is a standing
# offset: a given patch reads slightly warm to you all afternoon, and it reads
# warm every time you look. Splitting the error keeps the total per-look sigma
# honest while making repeat looks correlated. This share is the fraction of the
# error *variance* that is systematic.
BIAS_VARIANCE_SHARE = 0.35

# Fitting a ramp from every known cell on a long run would average noise nicely
# but drags in far anchors, and far anchors are where the hue-wrap ambiguity
# bites. Four damps noise while staying local.
MAX_ANCHORS = 4


def shown_labs(level: Level, k: float) -> list[tuple[float, float, float]]:
    """The board as presented, after similarity compression.

    Compression pulls every colour toward the board mean in OKLab, which scales
    every delta-E on the board by exactly (1 - k) because the map is an affine
    contraction and delta-E there is plain Euclidean distance. This mirrors
    TestingFilter in the app, whose whole design goal is that exactness.
    """
    labs = level.truth_lab
    if k <= 0.0:
        return list(labs)
    n = len(labs)
    mL = sum(v[0] for v in labs) / n
    ma = sum(v[1] for v in labs) / n
    mb = sum(v[2] for v in labs) / n
    s = 1.0 - k
    return [(mL + s * (v[0] - mL), ma + s * (v[1] - ma), mb + s * (v[2] - mb))
            for v in labs]


def _eye(level: Level, shown: list[tuple[float, float, float]],
         st: Settings, rng: random.Random):
    """Return (read, look): one fixed reading per colour, and a fresh-look function.

    `read` is what a player who lays the swatches out and sorts them has to work
    with: one reading per colour for the whole trial, standing bias and jitter
    baked in. `look` re-reads a colour with fresh jitter on top of the same
    standing bias, for the cell-by-cell player who keeps glancing back.
    """
    n = len(level.cells)
    bias_sigma = st.sigma * math.sqrt(BIAS_VARIANCE_SHARE) / 100.0 / math.sqrt(3.0)
    jitter = st.sigma * math.sqrt(1.0 - BIAS_VARIANCE_SHARE) / 100.0 / math.sqrt(3.0)
    gauss = rng.gauss
    if bias_sigma > 0.0:
        bias = [(gauss(0.0, bias_sigma), gauss(0.0, bias_sigma), gauss(0.0, bias_sigma))
                for _ in range(n)]
    else:
        bias = [(0.0, 0.0, 0.0)] * n

    def look(i: int) -> tuple[float, float, float]:
        v, b = shown[i], bias[i]
        if jitter <= 0.0:
            return (v[0] + b[0], v[1] + b[1], v[2] + b[2])
        return (v[0] + b[0] + gauss(0.0, jitter),
                v[1] + b[1] + gauss(0.0, jitter),
                v[2] + b[2] + gauss(0.0, jitter))

    return [look(i) for i in range(n)], look


@dataclass
class Decision:
    """One drag, for the verbose trace."""

    order: int
    why: str            # which channel decided it
    grad: int
    target: int
    chosen: int
    landed: int
    margin: float
    guessed: bool
    slipped: bool
    truth_gap: float    # dE between what was chosen and what belonged there


@dataclass
class Outcome:
    wrong: int
    guesses: int
    trace: list[Decision] | None = None

    @property
    def solved(self) -> bool:
        return self.wrong == 0


# ---------------------------------------------------------------------------
# Strategy `reason`: partition, order, orient, deduce
# ---------------------------------------------------------------------------
#
# The three perceptual jobs and the one logical job, in the order the player can
# do them:
#
#   partition  Which swatches belong to which run? Runs are painted in different
#              colour families, so this is a clustering judgement. It fails when
#              two families overlap inside the noise, which is what `run_sep`
#              measures.
#   order      A run is an even walk, so its swatches lie on a line, evenly
#              spaced. Sorting along that line needs only that consecutive steps
#              beat the noise, which is what `min_step` measures. It never needs
#              any cell's true colour, which is exactly what the old `match`
#              player got wrong.
#   orient     A sorted run can still go forwards or backwards. One given cell
#              off the run's centre settles it, or a crossing with a run already
#              placed. With no anchor at all, nothing settles it.
#   deduce     Two known cells on a run pin its whole ramp arithmetically, so
#              every remaining cell has a predicted colour and the nearest
#              swatch to that prediction is not a guess but a derivation. This
#              is the strongest channel and the player uses it first wherever it
#              is available.
#
# Rather than doing the three perceptual jobs as separate passes, the code folds
# them into one move: hypothesise a single swatch into the cell next to an
# anchor, which turns one known cell into two and therefore hands the rest of
# the run to deduction, then score the hypothesis by how well the deduced ramp
# finds swatches to fill itself with. Partition, ordering and orientation all
# fall out of that score. The mirror hypothesis (same swatch, other side of the
# anchor) is the reversal, so orientation is decided by comparing residuals, and
# when the anchor sits at the run's exact centre the two residuals are equal by
# symmetry and the coin flip appears on its own, with no special case.


def play_reason(level: Level, shown: list[tuple[float, float, float]],
                st: Settings, rng: random.Random, trace: bool = False) -> Outcome:
    """Read the board once, solve it, then check the work and try the other way.

    The retry is the human move this model would be dishonest without. A run
    that had to be seeded blind (no given cell anywhere on it) could have gone
    down either way round, and a person who lays one down, works outward from
    it and ends up with a run that visibly is not an even walk does not shrug:
    they flip it and redo. So the board is solved twice, once with the blind
    seed each way round, and the version whose runs read as more even wins.
    Evenness is measured on the player's own readings, never on the truth, so
    this stays a check a player could actually perform.
    """
    read, _ = _eye(level, shown, st, rng)
    seed = rng.randrange(1 << 30)
    first = _solve(level, read, st, random.Random(seed), trace)
    if first[3] is not None:          # something was decided on a coin
        second = _solve(level, read, st, random.Random(seed), trace,
                        avoid=first[3])
        if second[4] < first[4]:
            first = second
    content, guesses, records, _coin, _even = first
    wrong = sum(1 for i in level.bank if content[i] != i)
    return Outcome(wrong=wrong, guesses=guesses, trace=records)


def _evenness(level: Level, content: list[int | None], read) -> float:
    """How far the finished board is from every run being an even walk.

    Judged on what the player can see: their own reading of each placed colour
    against the ramp implied by that run's two end cells. Zero means every run
    looks perfect.
    """
    total = 0.0
    for path in level.gradients:
        m = len(path)
        if m < 3:
            continue                  # any two colours are an even walk
        ends = [(0, read[content[path[0]]]), (m - 1, read[content[path[-1]]])]
        for i in range(1, m - 1):
            total += lab_dist(read[content[path[i]]], _predict(ends, i))
    return total


def _solve(level: Level, read, st: Settings, rng: random.Random,
           trace: bool, avoid: tuple | None = None):
    """One pass over the board. `avoid` bans one option at the first coin flip.

    Banning it is how the caller gets a genuinely different second reading of
    the same board rather than the same coin landing the same way.
    """
    grads = level.gradients
    content: list[int | None] = [i if level.locked[i] else None
                                for i in range(len(level.cells))]
    pool = list(level.bank)
    empty = set(level.bank)
    guesses = 0
    coin: tuple | None = None         # the first decision that came down to a coin
    records: list[Decision] | None = [] if trace else None
    order = 0

    while pool:
        gi, tier, holes, known = _pick_run(level, content)
        path = grads[gi]
        plan: list[tuple[int, int, int, float, bool, str]] = []  # gi, cell, swatch, margin, forced, why
        ban = avoid if coin is None else None

        if tier == 0:
            # Two or more known cells: the ramp is arithmetic from here.
            preds = _fit_run(path, known, holes, content, read, pool,
                             _typical_step(level, content, read))
            for cell, swatch, margin, forced in _assign(preds, pool, read,
                                                        st.t, rng):
                plan.append((gi, cell, swatch, margin, forced, "deduce"))
        elif tier == 1:
            # Every run with one anchor is a judgement call, so make the easiest
            # one first: its swatches leave the bank, which is exactly the
            # information the harder calls were missing. Doing them in board
            # order instead is what made the model lose Penguin, where a short
            # run guessed at a swatch that a long run three moves later would
            # have claimed outright.
            plan = max((_orient_run(gj, gp, gh, gk, pool, read, st.t, rng, ban)
                        for gj, gp, gh, gk in _tier1_runs(level, content)),
                       key=lambda p: p[0][3])
        elif tier == 2:
            plan = _seed_blind(gi, path, holes, pool, read, st.t, rng, ban)
        else:
            # Leftovers: every run that is down to a single hole with no ramp to
            # derive it from. They are solved as one set rather than one at a
            # time, most confident first, so a hole with a decent guess cannot
            # have its swatch stolen by a hole with none. This is the counting
            # step a person does at the end of a board, and on a board where the
            # leftovers outnumber nothing it is pure elimination.
            jobs = []
            for gj, other in enumerate(grads):
                spare = [pos for pos, cell in enumerate(other)
                         if content[cell] is None]
                seen = [(pos, cell) for pos, cell in enumerate(other)
                        if content[cell] is not None]
                if len(spare) == 1 and len(seen) < 2:
                    jobs.append((gj, other[spare[0]],
                                 read[seen[0][1]] if seen else None))
            # These holes have one neighbour and no ramp, so the only thing
            # guiding them is scale: every run on a board steps at about the same
            # rate, and by now most of the board is down, so the player can see
            # what that rate is. Scoring a swatch by how far its step from the
            # anchor is from the board's typical step is what separates the right
            # leftover from a leftover that would merely sit closer. Choosing the
            # closest swatch instead is wrong, and measurably so: it is what made
            # the model fail Bird, Whale and their symmetric cousins.
            typical = _typical_step(level, content, read)
            table = {}
            for _, cell, pred in jobs:
                if pred is None or cell in table:
                    continue
                table[cell] = sorted(
                    (abs(lab_dist(read[s], pred) - typical), s) for s in pool)
            # Leftovers are decided as a set, not one at a time. Taking the
            # locally best swatch for each hole in turn is what a hurried player
            # does and it is wrong: it will happily give hole A the swatch that
            # fits it slightly better, leaving hole B with a step twice anything
            # else on the board. Minimising the total instead is both what a
            # careful player does and what the level intends.
            picked = {cell: (swatch, margin, forced) for cell, swatch, margin, forced
                      in _match_set(table, st.t, rng)}
            spare = [s for s in pool if s not in {v[0] for v in picked.values()}]
            for gj, cell, pred in jobs:
                if cell in picked:
                    swatch, margin, forced = picked[cell]
                    plan.append((gj, cell, swatch, margin, forced,
                                 "elimination" if margin == math.inf else "leftover"))
                elif spare:
                    # No anchor at all on the run, so nothing to aim at: a coin
                    # flip unless elimination has left exactly one swatch.
                    forced = len(spare) > 1
                    swatch = rng.choice(spare) if forced else spare[0]
                    spare.remove(swatch)
                    plan.append((gj, cell, swatch, 0.0 if forced else math.inf,
                                 forced, "blind" if forced else "elimination"))

        for gi, target, swatch, margin, forced, why in plan:
            if forced:
                guesses += 1
                if coin is None and tier in (1, 2):
                    coin = (target, swatch)
            if content[target] is not None:
                # An earlier slip in this same batch already filled the cell this
                # swatch was meant for, so the player puts it in the next hole on
                # the same run, or anywhere still empty if that run is full.
                spare = [c for c in grads[gi] if content[c] is None] \
                    or sorted(empty)
                if not spare:
                    break
                target = spare[0]
            landed, slipped = _maybe_slip(level, target, empty, st.misclick, rng)
            content[landed] = swatch
            empty.discard(landed)
            pool.remove(swatch)
            if records is not None:
                records.append(Decision(
                    order=order, why=why, grad=gi, target=target, chosen=swatch,
                    landed=landed, margin=margin, guessed=forced, slipped=slipped,
                    truth_gap=dist(level.truth[swatch], level.truth[landed])))
            order += 1
            if not pool:
                break

    return content, guesses, records, coin, _evenness(level, content, read)


def _tier1_runs(level: Level, content: list[int | None]):
    """Every run holding exactly one known cell and more than one hole."""
    out = []
    for gi, path in enumerate(level.gradients):
        holes = [pos for pos, cell in enumerate(path) if content[cell] is None]
        known = [(pos, cell) for pos, cell in enumerate(path)
                 if content[cell] is not None]
        if len(known) == 1 and len(holes) > 1:
            out.append((gi, path, holes, known))
    return out


def _fit_run(path: list[int], known: list[tuple[int, int]], holes: list[int],
             content: list[int | None], read, pool: list[int], typical: float):
    """Predict every hole on a deducible run, resolving how far the hue turned.

    Two known cells four apart whose hues differ by 160 degrees could be a ramp
    turning +40 a cell or one turning -50 a cell: the board cannot say, and the
    shorter reading is not always the right one (Cityscape's columns turn 200
    degrees end to end, so the short reading is wrong by 72 degrees a cell). The
    bank settles it. Fit the ramp the short way first, and if the colours it asks
    for are not in the bank, try the readings that go a full turn further each
    way and keep whichever one the bank actually answers.

    The early exit matters: on the great majority of runs the first fit lands on
    real swatches and the extra fits are never computed.
    """
    def build(turn: float):
        return [(path[pos],
                 _predict(_anchors(path, known, pos, content, read), pos, turn))
                for pos in holes]

    preds = build(0.0)
    if typical <= 0.0:
        return preds
    resid = sum(_nearest_dist(pred, pool, read) for _, pred in preds)
    if resid <= 0.25 * typical * len(holes):
        return preds
    best = (resid, preds)
    for turn in (-1.0, 1.0):
        trial = build(turn)
        r = sum(_nearest_dist(pred, pool, read) for _, pred in trial)
        if r < best[0]:
            best = (r, trial)
    return best[1]


def _typical_step(level: Level, content: list[int | None], read) -> float:
    """The step size the board is stepping at, as the player has seen it so far.

    Median rather than mean, so one badly placed cell cannot drag the estimate.
    Measured on the player's own readings of cells already down, never on the
    truth. Within a level the authored runs do step at similar rates (the median
    level's fastest run steps 1.6x its slowest), which is what makes this worth
    leaning on at all.
    """
    steps = []
    for path in level.gradients:
        for a, b in zip(path, path[1:]):
            if content[a] is not None and content[b] is not None:
                steps.append(lab_dist(read[content[a]], read[content[b]]))
    return statistics.median(steps) if steps else 0.0


def _pick_run(level: Level, content: list[int | None]):
    """Which run to work on next, by how much the board tells us about it.

    Tiers, strongest first: a run with two known cells can be deduced outright;
    a run with one known cell and room to grow can be sorted and oriented; a run
    with no known cell needs a blind seed; a run down to a single hole with
    nothing to derive it from is pure guesswork and is deferred, because doing it
    last lets elimination fill it for free.
    """
    best_key, best = None, None
    for gi, path in enumerate(level.gradients):
        holes = [pos for pos, cell in enumerate(path) if content[cell] is None]
        if not holes:
            continue
        known = [(pos, cell) for pos, cell in enumerate(path)
                 if content[cell] is not None]
        if len(holes) == 1 and len(known) < 2:
            tier = 3
        elif len(known) >= 2:
            tier = 0
        elif known:
            tier = 1
        else:
            tier = 2
        # Within a tier: most known cells first, then the fewest holes left, so
        # runs get finished rather than nibbled. The sign flips for a blind run:
        # there the move is a guess about which family belongs where, and the
        # longest run is the one to spend that guess on, because a long ramp is
        # the easiest family to recognise and it crosses the most other runs, so
        # getting it down turns the rest of the board into deduction.
        key = (tier, -len(known), -len(holes) if tier in (1, 2) else len(holes), gi)
        if best_key is None or key < best_key:
            best_key, best = key, (gi, tier, holes, known)
    return best


def _anchors(path: list[int], known: list[tuple[int, int]], pos: int,
             content: list[int | None], read) -> list[tuple[int, tuple]]:
    """The nearest known cells on the run, as (run position, reading)."""
    near = sorted(known, key=lambda kc: (abs(kc[0] - pos), kc[0]))[:MAX_ANCHORS]
    return [(kp, read[content[cell]]) for kp, cell in near]


def _orient_run(gi: int, path: list[int], holes: list[int],
                known: list[tuple[int, int]], pool: list[int], read,
                t: float, rng: random.Random, ban: tuple | None = None):
    """Place the one swatch that turns a sortable run into a deducible one.

    With a single anchor the run's step is unknown, so the move is to hypothesise
    a neighbour for the anchor. Each hypothesis (which swatch, which side) fixes
    a second cell and therefore a whole ramp, and the ramp is scored by how far
    its predictions land from the swatches actually left in the bank: the true
    orientation finds swatches sitting where it expects them, the reversal has to
    reach into other runs' families. The margin between the best and second-best
    hypothesis is the decision margin, so an anchor at the run's exact centre
    (where the two orientations are mirror images of each other) produces a
    margin of zero and a coin flip, which is the honest answer.
    """
    n = len(path)
    p = known[0][0]
    anchor_read = read[known[0][1]]
    sides = [q for q in (p - 1, p + 1) if 0 <= q < n and q in holes]
    cands = _nearest(anchor_read, pool, read, 2)

    scored = []
    for q in sides:
        for s in cands:
            rest = [x for x in holes if x != q]
            pairs = [(p, anchor_read), (q, read[s])]
            others = [x for x in pool if x != s]
            residual = sum(_nearest_dist(_predict(pairs, x), others, read)
                           for x in rest)
            residual += _overrun(pairs, n, holes, others, read)
            scored.append((residual, q, s))
    q, s, margin, forced = _pick_hypothesis(
        scored, t, rng, ban=(None if ban is None
                             else [(qq, ss) for _, qq, ss in scored
                                   if (path[qq], ss) == ban]))
    return [(gi, path[q], s, margin, forced, "orient")]


# How many candidate ramp ends to try when a run has to be seeded blind. The
# ranking below is good, so the true end is nearly always in the first few, and
# every extra candidate costs a full ramp evaluation.
SEED_CANDIDATES = 4


def _seed_blind(gi: int, path: list[int], holes: list[int], pool: list[int],
                read, t: float, rng: random.Random, ban: tuple | None = None):
    """Choose a family for a run that has no given cell anywhere on it.

    This is the partition step, and it is the hardest thing the player does.
    Three pieces of evidence, none of which needs a cell's true colour:

    1. A colour at the end of a ramp has one close neighbour and then a gap,
       while a colour in the middle of a ramp has two neighbours a step away on
       either side. Ranking the bank by that asymmetry puts the ramp ends at the
       top, and a run end has to be filled by a ramp end.
    2. Given an end and its neighbour, the whole ramp follows, so the hypothesis
       can be scored the same way orientation is: do the swatches the ramp asks
       for actually exist in the bank?
    3. The family has to be exactly as long as the run. If the ramp continues
       past the run's last cell and finds a swatch waiting there, this family
       belongs to a longer run, so the hypothesis is penalised (`_overrun`).

    What none of that settles is which way round the run goes: the two ends of a
    run are mirror images and score identically, so the direction is a coin flip
    here by construction. `ban` rules out the option a previous pass already
    tried, which is what lets the caller lay the board down both ways and keep
    the one that reads as more even.
    """
    n = len(path)
    ranked = []
    for s in pool:
        ds = sorted(lab_dist(read[s], read[o]) for o in pool if o != s)
        if not ds:
            continue
        d1 = ds[0]
        d2 = ds[1] if len(ds) > 1 else d1 * 4.0
        ranked.append((-(d2 / max(d1, 1e-9)), d1, s))
    ranked.sort()
    if not ranked:
        return []

    ends = [q for q in (0, n - 1) if q in holes] or [holes[0]]
    scored = []
    for _, _, s in ranked[:SEED_CANDIDATES]:
        rest_pool = [o for o in pool if o != s]
        if not rest_pool:
            continue
        s2 = min(rest_pool, key=lambda o: lab_dist(read[s], read[o]))
        for q in ends:
            q2 = q + 1 if q == 0 else q - 1
            if q2 not in holes:
                continue
            pairs = [(q, read[s]), (q2, read[s2])]
            others = [o for o in rest_pool if o != s2]
            residual = sum(_nearest_dist(_predict(pairs, x), others, read)
                           for x in holes if x not in (q, q2))
            residual += _overrun(pairs, n, holes, others, read)
            scored.append((residual, q, s, s2))
    if not scored:
        return []
    scored.sort()
    margin = math.inf if len(scored) == 1 else scored[1][0] - scored[0][0]
    forced = margin <= max(t, TIE_EPS)
    if forced:
        tied = [row for row in scored if row[0] <= scored[0][0] + max(t, TIE_EPS)]
        if ban:
            # The caller has already tried this seed and wants the other reading.
            other = [row for row in tied if (path[row[1]], row[2]) != ban]
            tied = other or tied
        _, q, s, s2 = rng.choice(tied)
    else:
        _, q, s, s2 = scored[0]
    q2 = q + 1 if q == 0 else q - 1
    return [(gi, path[q], s, margin, forced, "blind seed"),
            (gi, path[q2], s2, margin, False, "blind seed")]


def _pick_hypothesis(scored: list[tuple], t: float, rng: random.Random,
                     ban: list | None = None):
    scored.sort()
    margin = math.inf if len(scored) == 1 else scored[1][0] - scored[0][0]
    # `<=` and not `<` on purpose: an exact tie is the strongest possible coin
    # flip, and leaving it to `sort` would resolve it by swatch index, which is
    # the authored answer's own ordering. Every tie-break in this file has to go
    # through the rng for the model to be honest at sigma 0.
    forced = margin <= max(t, TIE_EPS)
    if forced:
        tied = [row for row in scored
                if row[0] <= scored[0][0] + max(t, TIE_EPS)]
        if ban:
            # The caller is re-reading the board and wants the other side of the
            # coin it already tried.
            other = [row for row in tied if (row[1], row[2]) not in ban]
            tied = other or tied
        _, q, s = rng.choice(tied)
    else:
        _, q, s = scored[0]
    return q, s, margin, forced


def _overrun(pairs: list[tuple[int, tuple]], n: int, holes: list[int],
             pool: list[int], read) -> float:
    """Penalty for a family that does not stop where the run stops.

    A run of six cells wants a family of exactly six colours. If the ramp the
    hypothesis implies keeps going past either end of the run and finds a swatch
    sitting exactly where the next step would land, then this family is really a
    longer run's, and putting it here will strand that longer run later. The
    penalty is scaled by the ramp's own step so it is comparable with the
    residual it is added to.
    """
    if len(pairs) < 2 or not pool:
        return 0.0
    (p0, v0), (p1, v1) = pairs[0], pairs[1]
    step = lab_dist(v0, v1) / max(abs(p1 - p0), 1)
    if step <= 0:
        return 0.0
    penalty = 0.0
    for beyond in (-1, n):
        if beyond in holes:
            continue
        d = _nearest_dist(_predict(pairs, beyond), pool, read)
        penalty += max(0.0, step - d)
    return penalty


def _nearest(target, pool: list[int], read, count: int) -> list[int]:
    return sorted(pool, key=lambda s: lab_dist(read[s], target))[:count]


def _nearest_dist(target, pool: list[int], read) -> float:
    if not pool:
        return 0.0
    tL, ta, tb = target
    best = None
    for s in pool:
        q = read[s]
        dL, da, db = (q[0] - tL) * 100, (q[1] - ta) * 100, (q[2] - tb) * 100
        d = dL * dL + da * da + db * db
        if best is None or d < best:
            best = d
    return math.sqrt(best)


def _assign(preds: list[tuple[int, tuple]], pool: list[int], read,
            t: float, rng: random.Random):
    """Match predicted colours to bank swatches by how far each swatch is."""
    table = {}
    for key, pred in preds:
        pL, pa, pb = pred
        ds = []
        for s in pool:
            q = read[s]
            dL, da, db = (q[0] - pL) * 100, (q[1] - pa) * 100, (q[2] - pb) * 100
            ds.append((math.sqrt(dL * dL + da * da + db * db), s))
        ds.sort()
        table[key] = ds
    return _match(table, t, rng)


# No decision may be resolved on a difference smaller than this, whatever `t`
# says. Distances that differ by 0.05 delta-E are the same distance to any eye
# (a JND is about 2), so a preference that small is arithmetic noise in the fit,
# not a signal, and letting it decide anything would quietly leak the answer key
# through rounding. It is the floor under every tie test in this file.
TIE_EPS = 0.05


# Above this many leftover holes the exact assignment is not worth its factorial,
# and the greedy one is close enough. Boards in this campaign top out at four.
EXACT_LIMIT = 6


def _match_set(table: dict, t: float, rng: random.Random):
    """Assign a small set of cells to swatches by minimising the total cost.

    The margin reported is the gap between the best whole assignment and the
    best assignment that differs from it, which is the right question for a set:
    "could these swatches have gone the other way round" rather than "is this
    cell's swatch clear". A gap under the threshold means the set as a whole was
    a coin flip.
    """
    keys = list(table)
    if not keys:
        return []
    if len(keys) > EXACT_LIMIT:
        return _match(table, t, rng)
    swatches = sorted({s for row in table.values() for _, s in row})
    cost = {(k, s): d for k in keys for d, s in table[k]}
    options = []
    for perm in itertools.permutations(swatches, len(keys)):
        options.append((sum(cost[(k, s)] for k, s in zip(keys, perm)), perm))
    options.sort(key=lambda o: o[0])
    best = options[0]
    margin = math.inf
    for total, perm in options[1:]:
        if perm != best[1]:
            margin = total - best[0]
            break
    forced = margin <= max(t, TIE_EPS)
    if forced:
        pick = rng.choice([o for o in options if o[0] <= best[0] + max(t, TIE_EPS)])
    else:
        pick = best
    return [(k, s, margin, forced) for k, s in zip(keys, pick[1])]


def _match(table: dict, t: float, rng: random.Random):
    """Greedy matching of cells to swatches, most confident cell first.

    Confidence order matters: filling the cell whose best candidate is clearest
    first means a cell the player is sure about never has its swatch stolen by a
    cell they are unsure about. Each cell keeps one sorted candidate list, so a
    run costs one pass over cells times bank rather than one per placement.
    """
    used: set[int] = set()
    pending = list(table)
    out = []
    while pending:
        rows = []
        for key in pending:
            avail = [(d, s) for d, s in table[key] if s not in used]
            rows.append((avail[0][0], key, avail))
        rows.sort(key=lambda row: (row[0], row[1]))
        d0, key, avail = rows[0]
        margin = math.inf if len(avail) == 1 else avail[1][0] - d0
        forced = margin <= max(t, TIE_EPS)   # see TIE_EPS: ties go to the coin
        if forced:
            swatch = rng.choice([s for d, s in avail if d <= d0 + t])
        else:
            swatch = avail[0][1]
        out.append((key, swatch, margin, forced))
        used.add(swatch)
        pending = [k for k in pending if k != key]
    return out


def _maybe_slip(level: Level, target: int, empty: set[int], p: float,
                rng: random.Random) -> tuple[int, bool]:
    if p <= 0.0 or len(empty) <= 1 or rng.random() >= p:
        return target, False
    near = [j for j in level.neighbours[target] if j in empty and j != target]
    pool = near or [j for j in empty if j != target]
    return (rng.choice(pool), True) if pool else (target, False)


# ---------------------------------------------------------------------------
# Strategy `match`: the careless player
# ---------------------------------------------------------------------------


def play_match(level: Level, shown: list[tuple[float, float, float]],
               st: Settings, rng: random.Random, trace: bool = False) -> Outcome:
    """Walk the board cell by cell, always dropping in the nearest swatch.

    This was the first model written and it is kept because it is a real way to
    play badly. It never sorts and it never checks a hypothesis, so a run with
    one central anchor is a coin flip it takes without noticing, an early
    mistake poisons every later extrapolation on that run, and it re-reads
    colours constantly (fresh jitter per glance) instead of reading once and
    reasoning. The gap between `match` and `reason` is the value of care.
    """
    _, look = _eye(level, shown, st, rng)
    content: list[int | None] = [i if level.locked[i] else None
                                 for i in range(len(level.cells))]
    pool = list(level.bank)
    empty = set(level.bank)
    guesses = 0
    records: list[Decision] | None = [] if trace else None
    order = 0

    while pool:
        gi, pos, target, anchors = _match_target(level, content, rng, look)
        expect = _predict(anchors, pos) if anchors else None
        if expect is None:
            # Nothing known on this run and nothing to extrapolate: the careless
            # player drops the most extreme swatch on a tip and hopes.
            seen = {j: look(j) for j in pool}
            m = len(seen)
            mid = tuple(sum(v[i] for v in seen.values()) / m for i in range(3))
            far = max(lab_dist(v, mid) for v in seen.values())
            tied = [j for j, v in seen.items() if lab_dist(v, mid) >= far - st.t]
            chosen, margin, forced = rng.choice(tied), 0.0, True
        else:
            scored = sorted((lab_dist(look(j), expect), j) for j in pool)
            best_d, best = scored[0]
            margin = math.inf if len(scored) == 1 else scored[1][0] - best_d
            forced = margin <= max(st.t, TIE_EPS)
            chosen = (rng.choice([j for d, j in scored
                                  if d <= best_d + max(st.t, TIE_EPS)])
                      if forced else best)
        if forced:
            guesses += 1
        landed, slipped = _maybe_slip(level, target, empty, st.misclick, rng)
        content[landed] = chosen
        empty.discard(landed)
        pool.remove(chosen)
        if records is not None:
            records.append(Decision(
                order=order, why="nearest", grad=gi, target=target, chosen=chosen,
                landed=landed, margin=margin, guessed=forced, slipped=slipped,
                truth_gap=dist(level.truth[chosen], level.truth[landed])))
        order += 1

    wrong = sum(1 for i in level.bank if content[i] != i)
    return Outcome(wrong=wrong, guesses=guesses, trace=records)


def _match_target(level: Level, content: list[int | None], rng: random.Random,
                  look):
    """Next hole for the careless player: most-known run, then closest to an anchor."""
    best_key, best = None, None
    for gi, path in enumerate(level.gradients):
        holes = [pos for pos, cell in enumerate(path) if content[cell] is None]
        if not holes:
            continue
        known = [(pos, cell) for pos, cell in enumerate(path)
                 if content[cell] is not None]
        key = (-len(known), len(holes) if known else -len(holes), gi)
        if best_key is None or key < best_key:
            best_key, best = key, (gi, path, holes, known)

    gi, path, holes, known = best
    if not known:
        pool = [c for c in level.tips if content[c] is None] \
            or [c for c in level.run_ends if content[c] is None] \
            or [path[holes[0]]]
        cell = rng.choice(pool)
        for gj, p in enumerate(level.gradients):
            if cell in p:
                return gj, p.index(cell), cell, []

    def hole_key(pos: int):
        gaps = [abs(kp - pos) for kp, _ in known]
        bracketed = (any(kp < pos for kp, _ in known)
                     and any(kp > pos for kp, _ in known))
        return (min(gaps), 0 if bracketed else 1, pos)

    pos = min(holes, key=hole_key)
    near = sorted(known, key=lambda kc: (abs(kc[0] - pos), kc[0]))[:MAX_ANCHORS]
    return gi, pos, path[pos], [(kp, look(content[cell])) for kp, cell in near]


# ---------------------------------------------------------------------------
# Ramp arithmetic, shared by both strategies
# ---------------------------------------------------------------------------


def _predict(pairs: list[tuple[int, tuple]], pos: int,
             turn: float = 0.0) -> tuple[float, float, float]:
    """Least-squares ramp fit in OKLCh through (run position, reading) pairs.

    Fitting in OKLCh rather than OKLab is load-bearing. The generator walks L, C
    and h at a constant step, so an even ramp is a straight line in LCh and, when
    hue rotates, a circular arc in OKLab. 38% of the authored gradients rotate
    hue, some by 149 degrees per cell, and a straight-line Lab fit on those is
    wrong by c * (2 sin(theta/2))^2, which is delta-E 6 at the median rotating
    step and delta-E 37 at the worst: larger than every bank margin on the board.
    The app's own solver carries the same warning in `stepConsistent`.
    """
    if len(pairs) == 1:
        # One known cell and no step: there is no ramp to extend, so the best
        # available guess is that the missing colour looks like its neighbour.
        return pairs[0][1]

    ps = [p for p, _ in pairs]
    Ls = [v[0] for _, v in pairs]
    Cs = [math.hypot(v[1], v[2]) for _, v in pairs]
    hs = [math.degrees(math.atan2(v[2], v[1])) for _, v in pairs]

    # Unwrap hue along the run before fitting, otherwise a ramp crossing 0
    # degrees fits a slope near zero and predicts the board average. The unwrap
    # assumes the smallest rotation consistent with the anchors, which is what a
    # person assumes, and is wrong in the same way a person is wrong when the
    # true step between the anchors on hand exceeds 180 degrees.
    order = sorted(range(len(ps)), key=lambda i: ps[i])
    prev = hs[order[0]]
    for i in order[1:]:
        while hs[i] - prev > 180.0:
            hs[i] -= 360.0
        while hs[i] - prev < -180.0:
            hs[i] += 360.0
        prev = hs[i]
    if turn:
        # `turn` asks for the reading where the hue makes that many extra full
        # turns between the first and last anchor, spread evenly. See `_fit_run`.
        first, last = ps[order[0]], ps[order[-1]]
        if last != first:
            for i in range(len(hs)):
                hs[i] += turn * 360.0 * (ps[i] - first) / (last - first)

    L = _linfit(ps, Ls, pos)
    C = _linfit(ps, Cs, pos)
    h = math.radians(_linfit(ps, hs, pos))
    # A negative fitted chroma is left alone: C * cos(h), C * sin(h) already
    # lands on the correct reflected point in Lab, which is the right answer for
    # a ramp the fit has pushed through the neutral axis.
    return (L, C * math.cos(h), C * math.sin(h))


def _linfit(ps: list[int], vs: list[float], at: float) -> float:
    n = len(ps)
    sp = sum(ps)
    spp = sum(p * p for p in ps)
    sv = sum(vs)
    spv = sum(p * v for p, v in zip(ps, vs))
    den = n * spp - sp * sp
    if den == 0:
        return sv / n
    slope = (n * spv - sp * sv) / den
    return (sv - slope * sp) / n + slope * at


STRATEGIES = {"reason": play_reason, "match": play_match}


# ---------------------------------------------------------------------------
# Trials
# ---------------------------------------------------------------------------


@dataclass
class LevelResult:
    level: Level
    settings: Settings
    trials: int
    success: float
    mean_wrong: float
    mean_guesses: float


def run_level(level: Level, st: Settings, trials: int,
              strategy: str = "reason") -> LevelResult:
    shown = shown_labs(level, st.k)
    play = STRATEGIES[strategy]
    solved = wrong_total = guess_total = 0
    for trial in range(trials):
        # Common random numbers: the seed depends only on the level and the
        # trial, never on the condition, the strategy or the clock. Two
        # conditions therefore start from the same draws, so a difference
        # between them is the condition rather than sampling luck, and any row
        # in the report reproduces with --level and --trials alone.
        out = play(level, shown, st, random.Random(level.index * 100003 + trial))
        solved += 1 if out.solved else 0
        wrong_total += out.wrong
        guess_total += out.guesses
    return LevelResult(level=level, settings=st, trials=trials,
                       success=solved / trials,
                       mean_wrong=wrong_total / trials,
                       mean_guesses=guess_total / trials)


DEFAULT_CONDITIONS = [
    # The control is not a playtest, it is the validity gate. A perfect eye must
    # solve every level that can be reasoned out at all, and any level it misses
    # is either a bug in the strategy or a level with no unique reasoned answer.
    Settings("noise-free control", sigma=0.0, k=0.0, t=0.0, misclick=0.0),
    Settings("sharp eye", sigma=1.0, k=0.0, t=1.5, misclick=0.0),
    Settings("typical eye", sigma=2.0, k=0.0, t=1.5, misclick=0.0),
    Settings("tired eye", sigma=3.0, k=0.0, t=1.5, misclick=0.0),
    Settings("compressed 50%", sigma=1.0, k=0.5, t=1.5, misclick=0.0),
    Settings("typical eye + fumbles", sigma=2.0, k=0.0, t=1.5, misclick=0.02),
]

CONTROL = "noise-free control"
# The condition the headline ranking and the correlations are measured against:
# sigma 2 is about one JND, the eye the game is authored for.
BASELINE = "typical eye"


# ---------------------------------------------------------------------------
# Statistics helpers (kept local: no numpy in this toolchain)
# ---------------------------------------------------------------------------


def pearson(xs: list[float], ys: list[float]) -> float:
    n = len(xs)
    if n < 3:
        return float("nan")
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if sxx <= 0 or syy <= 0:
        return float("nan")
    return sxy / math.sqrt(sxx * syy)


def _ranks(vs: list[float]) -> list[float]:
    order = sorted(range(len(vs)), key=lambda i: vs[i])
    ranks = [0.0] * len(vs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and vs[order[j + 1]] == vs[order[i]]:
            j += 1
        shared = (i + j) / 2.0 + 1.0
        for m in range(i, j + 1):
            ranks[order[m]] = shared
        i = j + 1
    return ranks


def spearman(xs: list[float], ys: list[float]) -> float:
    return pearson(_ranks(xs), _ranks(ys))


# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

CSV_HEADER = [
    "strategy", "condition", "sigma", "k", "t", "misclick",
    "index", "name", "chapter", "bankCount", "cells", "gradients",
    "run_separation", "min_step", "unpinned_runs", "analytic_margin",
    "effective_margin", "provably_ambiguous",
    "success_rate", "mean_wrong_cells", "mean_guesses",
]


def write_csv(path: Path, results: list[LevelResult], strategy: str) -> None:
    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(CSV_HEADER)
        for r in results:
            lv, st = r.level, r.settings
            w.writerow([
                strategy, st.label, f"{st.sigma:g}", f"{st.k:g}", f"{st.t:g}",
                f"{st.misclick:g}",
                lv.index, lv.name, lv.chapter, len(lv.bank), lv.cell_count,
                len(lv.gradients),
                f"{lv.run_sep:.2f}", f"{lv.min_step:.2f}", len(lv.unpinned),
                f"{lv.margin:.2f}", f"{lv.margin * (1.0 - st.k):.2f}",
                "yes" if lv.alt else "no",
                f"{r.success:.4f}", f"{r.mean_wrong:.3f}", f"{r.mean_guesses:.3f}",
            ])


def _table(head: list[str], rows: list[list[str]]) -> str:
    lines = ["| " + " | ".join(head) + " |",
             "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        lines.append("| " + " | ".join(r) + " |")
    return "\n".join(lines) + "\n"


def _short(label: str) -> str:
    return (label.replace("noise-free control", "control")
                 .replace("typical eye + fumbles", "fumbles")
                 .replace("compressed 50%", "k=0.5")
                 .replace(" eye", ""))


def build_report(levels: list[Level], results: list[LevelResult],
                 conditions: list[Settings], trials: int, strategy: str) -> str:
    by_cond: dict[str, dict[int, LevelResult]] = {}
    for r in results:
        by_cond.setdefault(r.settings.label, {})[r.level.index] = r
    labels = [c.label for c in conditions]
    played = [c for c in conditions if c.label != CONTROL]
    played_labels = [c.label for c in played]

    ctl = by_cond.get(CONTROL)
    fair = [lv for lv in levels if not lv.alt]
    unfair = [lv for lv in levels if lv.alt]

    out: list[str] = []
    out.append("# Campaign playtest, imperfect solver\n")

    # The gate comes first, before any difficulty number, because difficulty
    # numbers from an invalid control are noise about the model rather than
    # information about the levels.
    if ctl:
        solved = [lv for lv in levels if ctl[lv.index].success >= 1.0]
        missed = [lv for lv in levels if ctl[lv.index].success < 1.0]
        out.append(f"**CONTROL: {len(solved)}/{len(levels)} levels solved with a "
                   f"perfect eye** (sigma 0, k 0, t 0, no misclicks, "
                   f"strategy `{strategy}`).\n")
        if missed:
            proven = [lv for lv in missed if lv.alt]
            out.append(f"\n{len(missed)} levels are missed. All but "
                       f"{len(missed) - len(proven)} of them are **proved** "
                       "unfair below: a second arrangement exists that uses "
                       "exactly the bank swatches, keeps every given cell, and "
                       "shows every run as an even walk to within the app's own "
                       "sameness threshold, so no eye and no amount of thought "
                       "can choose between it and the authored answer. Any level "
                       "missed *without* such a proof is a suspected strategy "
                       "bug and is named as one.\n")
            out.append(f"\n{len(unfair)} levels carry that proof in total; the "
                       f"other {len(unfair) - len(proven)} are ones where the "
                       "alternative is even to within delta-E 2 but very "
                       "slightly less even than the authored answer, so a "
                       "literally perfect eye still picks the intended board "
                       "while a human eye could not.\n")
            out.append(_table(
                ["#", "name", "chapter", "bank", "unpinned runs", "control",
                 "verdict"],
                [[str(lv.index), lv.name, lv.chapter, str(len(lv.bank)),
                  str(len(lv.unpinned)), f"{ctl[lv.index].success:.0%}",
                  lv.alt or "UNEXPLAINED, suspect strategy"]
                 for lv in sorted(missed, key=lambda l: l.index)]))
            out.append("\nEvery difficulty number below is therefore reported over "
                       f"the {len(fair)} levels with a unique reasoned answer. The "
                       f"{len(unfair)} unfair levels are excluded from the "
                       "rankings, the chapter averages and the correlations, "
                       "because their failure rate measures a coin, not a "
                       "player.\n")

    out.append(f"\n{len(levels)} levels, {trials} trials per level per condition, "
               f"{len(conditions)} conditions, strategy `{strategy}` "
               f"({len(levels) * trials * len(conditions):,} simulated "
               "playthroughs). Every trial is seeded from the level index and "
               "the trial number alone, so conditions share their random draws "
               "and the whole file reproduces exactly.\n")

    def mean_success(idx: int, labs: list[str]) -> float:
        vals = [by_cond[l][idx].success for l in labs if idx in by_cond.get(l, {})]
        return sum(vals) / len(vals) if vals else float("nan")

    out.append("\n## The levels that fail hardest\n")
    out.append("Fair levels only, ranked by mean success across the played "
               "conditions. `sep` is the closest approach between two runs' "
               "colours, `step` the smallest step along a run, `margin` the "
               "closest pair in the bank.\n")
    ranked = sorted(fair, key=lambda lv: (mean_success(lv.index, played_labels),
                                          lv.index))
    out.append(_table(
        ["#", "name", "chapter", "bank", "sep", "step", "margin", "mean"] +
        [_short(l) for l in played_labels],
        [[str(lv.index), lv.name, lv.chapter, str(len(lv.bank)),
          f"{lv.run_sep:.1f}", f"{lv.min_step:.1f}", f"{lv.margin:.1f}",
          f"{mean_success(lv.index, played_labels):.0%}"] +
         [f"{by_cond[l][lv.index].success:.0%}" for l in played_labels]
         for lv in ranked[:20]]))

    base_label = BASELINE if BASELINE in by_cond else played_labels[-1]
    base = by_cond[base_label]
    base_st = next(c for c in conditions if c.label == base_label)
    out.append(f"\n## Where the difficulty comes from, at `{base_label}`\n")
    out.append(f"{base_st.describe()}, worst first, with the three channel "
               "measurements and the mean number of decisions the player was "
               "forced to guess on.\n")
    worst = sorted(fair, key=lambda lv: (base[lv.index].success, lv.index))[:20]
    out.append(_table(
        ["#", "name", "bank", "sep", "sep/sigma", "step", "step/sigma", "margin",
         "success", "wrong", "coin flips"],
        [[str(lv.index), lv.name, str(len(lv.bank)),
          f"{lv.run_sep:.1f}", f"{lv.run_sep / base_st.sigma:.1f}",
          f"{lv.min_step:.1f}", f"{lv.min_step / base_st.sigma:.1f}",
          f"{lv.margin:.1f}", f"{base[lv.index].success:.0%}",
          f"{base[lv.index].mean_wrong:.2f}",
          f"{base[lv.index].mean_guesses:.2f}"] for lv in worst]))

    out.append("\n## Per chapter\n")
    out.append("Mean success by chapter over fair levels, chapters in play order, "
               "so the columns should fall smoothly. A cliff is a pacing bug. "
               "`unfair` counts the levels excluded as provably ambiguous.\n")
    chapters: list[str] = []
    for lv in sorted(levels, key=lambda l: l.index):
        if lv.chapter not in chapters:
            chapters.append(lv.chapter)
    rows = []
    for ch in chapters:
        members = [lv for lv in fair if lv.chapter == ch]
        all_members = [lv for lv in levels if lv.chapter == ch]
        row = [ch, f"{all_members[0].index}-{all_members[-1].index}",
               str(sum(1 for lv in all_members if lv.alt))]
        if members:
            row += [f"{statistics.fmean(lv.run_sep for lv in members):.1f}",
                    f"{statistics.fmean(lv.min_step for lv in members):.1f}"]
            row += [f"{statistics.fmean(by_cond[l][lv.index].success for lv in members):.0%}"
                    for l in labels]
        else:
            row += ["-", "-"] + ["-" for _ in labels]
        rows.append(row)
    out.append(_table(["chapter", "levels", "unfair", "mean sep", "mean step"] +
                      [_short(l) for l in labels], rows))

    out.append("\n## Which measurement predicts failure?\n")
    ys = [base[lv.index].success for lv in fair]
    preds = {
        "between-run separation": [lv.run_sep for lv in fair],
        "within-run step": [lv.min_step for lv in fair],
        "unpinned runs (count)": [float(len(lv.unpinned)) for lv in fair],
        "hardest bank margin": [lv.margin for lv in fair],
        "bank size": [float(len(lv.bank)) for lv in fair],
    }
    out.append(f"Correlation with success rate at `{base_label}` over the "
               f"{len(fair)} fair levels. Positive means more of the quantity is "
               "an easier level, so the channel measurements should come out "
               "positive and `unpinned runs` negative.\n")
    out.append(_table(
        ["quantity", "Pearson r", "Spearman rho"],
        [[name, f"{pearson(xs, ys):+.3f}", f"{spearman(xs, ys):+.3f}"]
         for name, xs in preds.items()]))
    out.append("\nBank size is in the table as a confound check: late levels have "
               "both tighter colours and more decisions, so a channel measurement "
               "only earns its keep if it beats plain counting. Success is a "
               "whole-board test, so it punishes size twice over (thirty "
               "decisions at 99% each still lose a quarter of the time). The "
               "table below removes that by asking the same question per cell.\n")
    per_cell = [base[lv.index].mean_wrong / max(len(lv.bank), 1) for lv in fair]
    out.append(_table(
        ["quantity", "Pearson r vs per-cell error", "Spearman rho"],
        [[name, f"{pearson(xs, per_cell):+.3f}", f"{spearman(xs, per_cell):+.3f}"]
         for name, xs in preds.items()]))
    out.append("\nNegative is what a difficulty measurement should be here: more "
               "separation, fewer errors. Note that `within-run step` and "
               f"`hardest bank margin` are the same number on "
               f"{sum(1 for lv in fair if abs(lv.min_step - lv.margin) < 0.01)} of "
               f"the {len(fair)} fair levels, because the closest pair in the bank "
               "is almost always two neighbours on one run. The step is the more "
               "useful of the two to author against, since it is the quantity the "
               "generator can set directly.\n")

    def band(v: float, sigma: float) -> str:
        if sigma <= 0:
            return "n/a"
        r = v / sigma
        if r < 2.0:
            return "under 2 sigma (coin flip)"
        if r < 3.0:
            return "2 to 3 sigma (strained)"
        if r < 5.0:
            return "3 to 5 sigma (workable)"
        return "over 5 sigma (comfortable)"

    for name, xs in (("between-run separation", [lv.run_sep for lv in fair]),
                     ("within-run step", [lv.min_step for lv in fair])):
        rows = []
        for b in ("under 2 sigma (coin flip)", "2 to 3 sigma (strained)",
                  "3 to 5 sigma (workable)", "over 5 sigma (comfortable)"):
            members = [lv for lv, x in zip(fair, xs)
                       if band(x, base_st.sigma) == b]
            if not members:
                continue
            rows.append([b, str(len(members)),
                         f"{statistics.fmean(base[lv.index].success for lv in members):.0%}",
                         f"{statistics.fmean(base[lv.index].mean_wrong for lv in members):.2f}"])
        out.append(f"\nBanded by {name} against the perceptual noise:\n")
        out.append(_table(["band", "levels", "mean success", "mean wrong cells"],
                          rows))

    out.append("\n## Settings used\n")
    out.append(_table(
        ["condition", "sigma", "k", "t", "misclick", "mean success (fair)",
         "fair levels above 90%"],
        [[c.label, f"{c.sigma:g}", f"{c.k:g}", f"{c.t:g}", f"{c.misclick:g}",
          f"{statistics.fmean(by_cond[c.label][lv.index].success for lv in fair):.0%}",
          str(sum(1 for lv in fair if by_cond[c.label][lv.index].success >= 0.9))]
         for c in conditions]))
    out.append("\nParameter meanings, all in delta-E units scaled x100 as in "
               "`oklch.dist` (one JND is about 2):\n\n"
               f"- `sigma`: total perceptual error per reading, split so that "
               f"{BIAS_VARIANCE_SHARE:.0%} of the variance is a standing bias "
               "per colour (identical every time that colour is read) and the "
               "rest is fresh jitter.\n"
               "- `k`: similarity compression toward the board mean in OKLab, "
               "which scales every board delta-E by exactly (1 - k), as "
               "TestingFilter does in the app.\n"
               "- `t`: decision margin below which the player cannot tell the "
               "winner from the runner-up and picks at random among the tied "
               "candidates.\n"
               "- `misclick`: chance a drag lands in a different empty cell, "
               "preferring one adjacent to the intended cell.\n")

    out.append("\n## What this model does not capture\n")
    out.append(
        "- The `reason` player never backtracks across runs. Once a run is laid "
        "down it stays down, so a partition mistake early on cannot be undone "
        "by noticing that a later run has become unfillable. A determined "
        "person would notice.\n"
        "- Partition is done implicitly, by scoring the ramp a hypothesis "
        "implies against the swatches still in the bank. That is weaker than a "
        "person eyeing the whole pile and spotting three colour families at "
        "once, and it is where the model most likely understates a careful "
        "player.\n"
        "- Elimination is only used at the very end, when a run is down to one "
        "hole. Counting arguments in the middle of a board (this family has "
        "five members and that run has five holes) are not modelled.\n"
        "- Hue steps above 180 degrees between the anchors on hand are read as "
        "the shorter rotation, because nothing on the board disambiguates them.\n"
        "- Compression is applied in OKLab, so at k > 0 an evenly stepped LCh "
        "ramp is no longer evenly stepped in the space the player fits. The "
        "compressed condition therefore mixes reduced discriminability with a "
        "genuine model bias, and its absolute numbers should be read as a "
        "direction rather than a measurement.\n"
        "- sigma, t and the bias share are asserted, not measured against "
        "humans. Only their ordering is trustworthy.\n"
        "- The two strategies are not given the same number of looks, and it "
        "flatters the careless one. `reason` reads every colour once and then "
        "reasons on those readings, while `match` re-reads on every comparison "
        "and so averages part of its own jitter away. Letting `reason` read "
        "each colour two or three times instead moves it from 64% to 69% and "
        "71% at `typical eye`, against 65% for `match`, so the careful player's "
        "real advantage under noise is around five points and the sweep below "
        "shows none of it. The zero-noise control, where reading twice changes "
        "nothing, is the honest comparison: 100% against 89%.\n")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Verbose single level
# ---------------------------------------------------------------------------


def report_one(level: Level, st: Settings, trials: int, strategy: str) -> None:
    shown = shown_labs(level, st.k)
    print(f"level {level.index}  {level.name}  ({level.chapter})")
    print(f"  grid {level.grid_w}x{level.grid_h}, {level.cell_count} cells, "
          f"{len(level.gradients)} gradients, bank {len(level.bank)}, "
          f"locked {level.cell_count - len(level.bank)}")
    print(f"  strategy {strategy}, condition {st.label}: {st.describe()}")
    print(f"  between-run separation dE {level.run_sep:.2f}"
          + (f" at {level.cells[level.run_sep_pair[0]]} vs "
             f"{level.cells[level.run_sep_pair[1]]}" if level.run_sep_pair else ""))
    print(f"  smallest within-run step dE {level.min_step:.2f}")
    print(f"  hardest bank margin    dE {level.margin:.2f}"
          + (f" at {level.cells[level.margin_pair[0]]} vs "
             f"{level.cells[level.margin_pair[1]]}" if level.margin_pair else ""))
    if level.unpinned:
        print(f"  runs with no anchor: {level.unpinned} "
              f"(of {len(level.gradients)})")
    print(f"  second valid arrangement: {level.alt or 'none found'}")

    print("\n  trial 0, decision by decision:")
    out = STRATEGIES[strategy](level, shown, st,
                               random.Random(level.index * 100003), trace=True)
    print("    step  why          grad target        chose         margin  note")
    for d in out.trace or []:
        note = []
        if d.guessed:
            note.append("COIN FLIP")
        if d.slipped:
            note.append(f"slipped to {level.cells[d.landed]}")
        # Correct means the swatch ended up in the cell it was authored for, so a
        # slip that happens to land right still counts as right.
        note.append("ok" if d.chosen == d.landed
                    else f"WRONG by dE {d.truth_gap:.1f}")
        margin = "   inf" if d.margin == math.inf else f"{d.margin:6.2f}"
        print(f"    {d.order:4d}  {d.why:12s} {d.grad:4d} "
              f"{str(level.cells[d.target]):13s} "
              f"{str(level.cells[d.chosen]):13s} {margin}  {', '.join(note)}")
    print(f"  trial 0 result: {out.wrong} wrong cells, {out.guesses} coin flips")

    res = run_level(level, st, trials, strategy)
    print(f"\n  over {trials} trials: success {res.success:.1%}, "
          f"mean wrong cells {res.mean_wrong:.2f}, "
          f"mean coin flips {res.mean_guesses:.2f}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--campaign", type=Path, default=CAMPAIGN)
    ap.add_argument("--strategy", choices=sorted(STRATEGIES), default="reason",
                    help="reason = careful sorting player, match = careless one")
    ap.add_argument("--level", type=int, help="run one level verbosely")
    ap.add_argument("--trials", type=int, default=200)
    ap.add_argument("--sigma", type=float, help="override perceptual noise")
    ap.add_argument("--k", type=float, help="override similarity compression")
    ap.add_argument("--t", type=float, help="override indistinguishability threshold")
    ap.add_argument("--misclick", type=float, help="override misclick probability")
    ap.add_argument("--csv", type=Path, default=HERE / "playtest.csv")
    ap.add_argument("--report", type=Path, default=HERE / "playtest-report.md")
    args = ap.parse_args(argv)

    levels = load_levels(args.campaign)

    # Any explicit knob collapses the sweep to a single named condition, so
    # --sigma means "simulate this eye" rather than "add a seventh row".
    overrides = {k: v for k, v in (("sigma", args.sigma), ("k", args.k),
                                   ("t", args.t), ("misclick", args.misclick))
                 if v is not None}
    if overrides:
        conditions = [Settings("custom", **{**{"sigma": 2.0, "k": 0.0, "t": 1.5,
                                               "misclick": 0.0}, **overrides})]
    else:
        conditions = list(DEFAULT_CONDITIONS)

    if args.level is not None:
        match = [lv for lv in levels if lv.index == args.level]
        if not match:
            print(f"no level {args.level} in {args.campaign}", file=sys.stderr)
            return 2
        st = conditions[0] if overrides else next(
            c for c in DEFAULT_CONDITIONS if c.label == BASELINE)
        report_one(match[0], st, args.trials, args.strategy)
        return 0

    results: list[LevelResult] = []
    for st in conditions:
        print(f"  {st.label:22s} {st.describe()}", file=sys.stderr)
        for lv in levels:
            results.append(run_level(lv, st, args.trials, args.strategy))

    write_csv(args.csv, results, args.strategy)
    args.report.write_text(build_report(levels, results, conditions, args.trials,
                                        args.strategy))

    ctl = {r.level.index: r for r in results if r.settings.label == CONTROL}
    if ctl:
        good = sum(1 for r in ctl.values() if r.success >= 1.0)
        print(f"CONTROL: {good}/{len(levels)} levels solved with a perfect eye "
              f"(strategy {args.strategy})")
        bad = [r.level for r in ctl.values() if r.success < 1.0]
        proven = [lv for lv in bad if lv.alt]
        if bad:
            print(f"  {len(proven)} proved ambiguous, "
                  f"{len(bad) - len(proven)} unexplained")
            for lv in sorted(bad, key=lambda l: l.index):
                if not lv.alt:
                    print(f"    UNEXPLAINED {lv.index} {lv.name}")
    print(f"wrote {args.csv}")
    print(f"wrote {args.report}")

    fair = {lv.index for lv in levels if not lv.alt}
    by_index: dict[int, list[LevelResult]] = {}
    for r in results:
        if r.settings.label != CONTROL and r.level.index in fair:
            by_index.setdefault(r.level.index, []).append(r)
    ranked = sorted(by_index.items(),
                    key=lambda kv: statistics.fmean(r.success for r in kv[1]))
    print("\nworst ten fair levels (mean success across played conditions):")
    for idx, rs in ranked[:10]:
        lv = rs[0].level
        print(f"  {idx:3d} {lv.name:12s} bank={len(lv.bank):2d} "
              f"sep={lv.run_sep:5.2f} step={lv.min_step:5.2f} "
              f"margin={lv.margin:5.2f}  "
              f"{statistics.fmean(r.success for r in rs):6.1%}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
