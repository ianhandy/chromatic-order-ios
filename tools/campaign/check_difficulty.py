"""Check that the built campaign actually sits on its difficulty curve.

`build.py` searches bank sizes and palettes until a level measures close to the
target in `BOOK2_DIFFICULTY`, and records what it settled for in the level's
`typicalWrong`. This re-measures every board from the shipped JSON and holds
the result against that target, so three separate things get caught:

  * a board a perfect eye cannot land, which is a defect however it got there;
  * a level far off its intended difficulty, which is the curve drifting;
  * a `typicalWrong` that disagrees with the board it is attached to, which
    means the resource was hand-edited or the JSON is stale.

The recorded number is deliberately not trusted. Checking build.py's own note
of what it did would only ever prove build.py agrees with itself.

    python3 check_difficulty.py [campaign.json]
"""

from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build  # noqa: E402
import playtest  # noqa: E402

CAMPAIGN = build.OUT_JSON

# Wider than the search's own tolerance, because a shape that cannot reach its
# target inside the bank window keeps the closest it managed, and that is a
# fact about the shape rather than a fault. This catches a curve that has come
# loose, not a level that is a little off it.
TOLERANCE = 1.5
# The recorded number and a fresh measurement run the same trials on the same
# board, so they should agree exactly; the slack is for the rounding in the
# JSON and nothing else.
RECORD_SLACK = 0.02


def measure(entry: dict) -> tuple[int, bool, float]:
    level = playtest._level_from_entry(entry)
    control = playtest.Settings("noise-free control", sigma=0.0, k=0.0, t=0.0,
                                misclick=0.0)
    landed = playtest.run_level(level, control, build.CONTROL_TRIALS,
                                "reason").success >= 1.0
    typical = playtest.Settings("typical eye", sigma=2.0, k=0.0, t=1.5,
                                misclick=0.0)
    wrong = playtest.run_level(level, typical, build.TUNE_TRIALS,
                               "reason").mean_wrong
    return entry["index"], landed, wrong


def main(argv: list[str]) -> int:
    path = Path(argv[0]) if argv else CAMPAIGN
    levels = json.loads(path.read_text())["levels"]
    tuned = [lv for lv in levels if build.difficulty_target(lv["index"]) is not None]
    if not tuned:
        print("  no levels carry a difficulty target")
        return 1

    with ProcessPoolExecutor() as pool:
        measured = {i: (ok, w) for i, ok, w in pool.map(measure, tuned, chunksize=4)}

    problems: list[str] = []
    by_chapter: dict[str, list[float]] = defaultdict(list)
    order: list[str] = []

    for entry in tuned:
        index = entry["index"]
        where = f"level {index} ({entry['name']})"
        target = build.difficulty_target(index)
        landed, wrong = measured[index]
        by_chapter[entry["chapter"]].append(wrong)
        if entry["chapter"] not in order:
            order.append(entry["chapter"])

        if not landed:
            problems.append(f"{where}: a perfect eye does not land this board")
        if abs(wrong - target) > TOLERANCE:
            problems.append(
                f"{where}: leaves {wrong:.2f} cells wrong against a target of "
                f"{target:.2f}")
        recorded = entry.get("typicalWrong")
        if recorded is None:
            problems.append(f"{where}: carries no typicalWrong")
        elif abs(recorded - wrong) > RECORD_SLACK:
            problems.append(
                f"{where}: records {recorded:.2f} wrong but measures "
                f"{wrong:.2f}, so the resource is stale")

    print(f"  {'chapter':14} {'levels':>6} {'mean':>6} {'worst':>6}")
    previous = None
    for chapter in order:
        got = by_chapter[chapter]
        mean = statistics.fmean(got)
        print(f"  {chapter:14} {len(got):6d} {mean:6.2f} {max(got):6.2f}")
        if previous is not None and mean < previous:
            problems.append(
                f"chapter {chapter} averages {mean:.2f} wrong, easier than the "
                f"chapter before it at {previous:.2f}")
        previous = mean

    print(f"\n  {len(tuned)} levels measured")
    if problems:
        print(f"\n  {len(problems)} problems:")
        for problem in problems:
            print(f"    {problem}")
        return 1
    print("  every level sits on its curve")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
