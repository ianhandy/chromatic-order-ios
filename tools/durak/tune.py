"""Parameter sweeps. The numbers in policy.py and run.py come from here.

Tuning a roguelike by taste is how you ship a game that is trivial for the
designer and impossible for everyone else. Every magic number these modules
carry should be traceable to a sweep in this file, the same way the campaign's
difficulty gates trace back to tools/campaign/playtest.py rather than to
somebody's feel for it.

Usage:
    python3 tune.py exchange      # what is a wound worth, in trump points?
    python3 tune.py discipline    # when should you attack with a trump?
    python3 tune.py difficulty    # does the gauntlet produce a real curve?
    python3 tune.py relics        # which relics are broken?
"""

from __future__ import annotations

import statistics
import sys
from dataclasses import replace

import policy
from policy import SKILLS, Skill
from run import ARCHETYPES, RunConfig, play_run
from relics import CATALOGUE

# One seed count for every sweep, so two tables can be read against each other.
SEEDS = 600


def with_skill(key: str, **changes) -> None:
    """Patch a skill in place for the duration of a sweep."""
    SKILLS[key] = replace(SKILLS[key], **changes)


def measure(skill_key: str, seeds: int, archetype: str = "balanced",
            config: RunConfig | None = None, relics: list[str] | None = None):
    depths, healths = [], []
    for s in range(seeds):
        state = play_run(s, skill_key, archetype, config, relics)
        depths.append(state.depth_reached)
        healths.append(state.health)
    n = len(depths)
    return {
        "mean_depth": statistics.mean(depths),
        "clear_rate": sum(1 for d in depths if d >= (config or RunConfig()).encounters) / n,
        "wipe_rate": sum(1 for d in depths if d == 0) / n,
        "mean_health": statistics.mean(healths),
    }


def sweep_exchange(seeds: int = SEEDS) -> None:
    print("What is one wound worth, in trump points?")
    print("(exchange 99 = never surrender voluntarily)\n")
    print(f"{'exchange':>9} {'mean depth':>11} {'clears':>8} {'wipes':>7}")
    baseline = SKILLS["sharp"]
    for x in (1, 2, 3, 5, 8, 12, 20, 40, 99):
        SKILLS["sharp"] = replace(baseline, exchange=float(x))
        m = measure("sharp", seeds)
        print(f"{x:>9} {m['mean_depth']:>11.2f} {m['clear_rate']:>7.0%} {m['wipe_rate']:>6.0%}")
    SKILLS["sharp"] = baseline


def sweep_discipline(seeds: int = SEEDS) -> None:
    print("How readily should you spend a trump as an ATTACK card?")
    print("(0 dumps every trump, 1 never leads one while the talon lasts)\n")
    print(f"{'discipline':>11} {'mean depth':>11} {'clears':>8} {'wipes':>7}")
    baseline = SKILLS["sharp"]
    for d in (0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0):
        SKILLS["sharp"] = replace(baseline, trump_discipline=d)
        m = measure("sharp", seeds)
        print(f"{d:>11.2f} {m['mean_depth']:>11.2f} {m['clear_rate']:>7.0%} {m['wipe_rate']:>6.0%}")
    SKILLS["sharp"] = baseline


def sweep_difficulty(seeds: int = SEEDS) -> None:
    print("Does the gauntlet separate skill levels, and is it survivable?\n")
    print(f"{'skill':>9} {'mean depth':>11} {'clears':>8} {'wipes':>7} {'health left':>12}")
    for key in ("sharp", "typical", "tired", "reckless"):
        m = measure(key, seeds)
        print(f"{key:>9} {m['mean_depth']:>11.2f} {m['clear_rate']:>7.0%} "
              f"{m['wipe_rate']:>6.0%} {m['mean_health']:>12.1f}")


def sweep_relics(seeds: int = SEEDS) -> None:
    print("Each relic, granted from the start, against the vanilla baseline.\n")
    base = measure("typical", seeds)
    print(f"{'relic':>16} {'mean depth':>11} {'clears':>8} {'delta':>7}")
    print(f"{'(none)':>16} {base['mean_depth']:>11.2f} {base['clear_rate']:>7.0%} {'--':>7}")
    rows = []
    for key in sorted(CATALOGUE):
        m = measure("typical", seeds, relics=[key])
        rows.append((m["mean_depth"] - base["mean_depth"], key, m))
    for delta, key, m in sorted(rows, reverse=True):
        print(f"{CATALOGUE[key].name:>16} {m['mean_depth']:>11.2f} {m['clear_rate']:>7.0%} {delta:>+7.2f}")


def sweep_archetypes(seeds: int = SEEDS) -> None:
    print("Shopping policies, all at typical skill.\n")
    print(f"{'archetype':>13} {'mean depth':>11} {'clears':>8} {'wipes':>7}")
    for a in ARCHETYPES:
        m = measure("typical", seeds, archetype=a)
        print(f"{a:>13} {m['mean_depth']:>11.2f} {m['clear_rate']:>7.0%} {m['wipe_rate']:>6.0%}")


def sweep_health(seeds: int = SEEDS) -> None:
    print("Does the wound system ever bind?\n")
    print(f"{'health':>7} {'mean depth':>11} {'clears':>8} {'wipes':>7} {'left':>6} "
          f"{'Ironbound':>10} {'Surgeon':>9}")
    for h in (6, 8, 10, 12, 16, 20, 30):
        cfg = RunConfig(starting_health=h)
        base = measure("typical", seeds, config=cfg)
        iron = measure("typical", seeds, config=cfg, relics=["ironbound"])
        surg = measure("typical", seeds, config=cfg, relics=["field_surgeon"])
        print(f"{h:>7} {base['mean_depth']:>11.2f} {base['clear_rate']:>7.0%} "
              f"{base['wipe_rate']:>6.0%} {base['mean_health']:>6.1f} "
              f"{iron['mean_depth'] - base['mean_depth']:>+10.2f} "
              f"{surg['mean_depth'] - base['mean_depth']:>+9.2f}")


def _per_depth(skill: str, seeds: int) -> list[tuple[int, int, float, float]]:
    from collections import defaultdict
    reached, won, wounds = defaultdict(int), defaultdict(int), defaultdict(int)
    for s in range(seeds):
        for r in play_run(s, skill, "balanced").log:
            reached[r.depth] += 1
            if r.won:
                won[r.depth] += 1
            elif r.health_after <= 0:
                wounds[r.depth] += 1
    rows = []
    for d in sorted(reached):
        lost = reached[d] - won[d]
        rows.append((d, reached[d], won[d] / reached[d], wounds[d] / lost if lost else 0.0))
    return rows


def write_report(path: str = "playtest-report.md", seeds: int = SEEDS) -> None:
    """Emit the markdown report. Regenerate with `python3 tune.py report`."""
    from run import OPPONENT_NAMES, RunConfig, opponent_for
    from engine import SeededRNG as _R

    out: list[str] = []
    w = out.append
    cfg = RunConfig()
    w("# Durak roguelike, simulated playtest")
    w("")
    w(f"{seeds} seeded runs per condition, {cfg.encounters} encounters per run, "
      f"{cfg.starting_health} starting health. Every run is seeded from its index "
      "alone, and deck draws are seeded separately from policy noise, so the "
      "conditions below share their shuffles and the whole file reproduces exactly.")
    w("")
    w("Regenerate with `python3 tune.py report`.")
    w("")

    w("## Does the gauntlet separate skill levels?")
    w("")
    w("`reckless` is a control, not a skill level: it never gives up a bout.")
    w("")
    w("| condition | mean depth | clears | wiped at the first | health left |")
    w("|---|---|---|---|---|")
    for key in ("sharp", "typical", "tired", "reckless"):
        m = measure(key, seeds)
        w(f"| {key} | {m['mean_depth']:.2f} | {m['clear_rate']:.0%} | "
          f"{m['wipe_rate']:.0%} | {m['mean_health']:.1f} |")
    w("")

    w("## Where runs actually end")
    w("")
    w("| depth | opponent | reached (sharp) | win rate (sharp) | reached (typical) | win rate (typical) | lost to wounds (typical) |")
    w("|---|---|---|---|---|---|---|")
    sharp_rows = {r[0]: r for r in _per_depth("sharp", seeds)}
    typ_rows = {r[0]: r for r in _per_depth("typical", seeds)}
    for d in sorted(typ_rows):
        sr, tr = sharp_rows.get(d), typ_rows[d]
        name = opponent_for(d, _R(d)).name
        w(f"| {d} | {name} | {sr[1] if sr else 0} | {sr[2]:.0%} | {tr[1]} | {tr[2]:.0%} | {tr[3]:.0%} |")
    w("")

    w("## Relic power, granted from the start")
    w("")
    base = measure("typical", seeds)
    w(f"Baseline is a typical player with no relics: mean depth {base['mean_depth']:.2f}, "
      f"{base['clear_rate']:.0%} clears.")
    w("")
    w("| relic | mean depth | clears | delta | text |")
    w("|---|---|---|---|---|")
    rows = []
    for key in sorted(CATALOGUE):
        m = measure("typical", seeds, relics=[key])
        rows.append((m["mean_depth"] - base["mean_depth"], key, m))
    for delta, key, m in sorted(rows, reverse=True):
        w(f"| {CATALOGUE[key].name} | {m['mean_depth']:.2f} | {m['clear_rate']:.0%} | "
          f"{delta:+.2f} | {CATALOGUE[key].text} |")
    w("")

    w("## Shopping policies")
    w("")
    w("| archetype | mean depth | clears | wiped at the first |")
    w("|---|---|---|---|")
    for a in ARCHETYPES:
        m = measure("typical", seeds, archetype=a)
        w(f"| {a} | {m['mean_depth']:.2f} | {m['clear_rate']:.0%} | {m['wipe_rate']:.0%} |")
    w("")

    w("## Does health bind?")
    w("")
    w("Ironbound exists only to blunt wounds, so its value is a direct readout "
      "of whether the wound system is doing anything.")
    w("")
    w("| starting health | mean depth | clears | wiped at the first | health left | Ironbound is worth |")
    w("|---|---|---|---|---|---|")
    for h in (4, 6, 8, 10, 12, 16, 20, 30):
        c = RunConfig(starting_health=h)
        b = measure("typical", seeds, config=c)
        i = measure("typical", seeds, config=c, relics=["ironbound"])
        w(f"| {h} | {b['mean_depth']:.2f} | {b['clear_rate']:.0%} | {b['wipe_rate']:.0%} | "
          f"{b['mean_health']:.1f} | {i['mean_depth'] - b['mean_depth']:+.2f} |")
    w("")

    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")
    print(f"wrote {path} ({seeds} runs per condition)")


SWEEPS = {
    "report": write_report,
    "health": sweep_health,
    "exchange": sweep_exchange,
    "discipline": sweep_discipline,
    "difficulty": sweep_difficulty,
    "relics": sweep_relics,
    "archetypes": sweep_archetypes,
}

if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "difficulty"
    if name not in SWEEPS:
        raise SystemExit(f"unknown sweep {name!r}; have {', '.join(SWEEPS)}")
    SWEEPS[name]()
