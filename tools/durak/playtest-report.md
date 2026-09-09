# Durak roguelike, simulated playtest

600 seeded runs per condition, 8 encounters per run, 8 starting health. Every run is seeded from its index alone, and deck draws are seeded separately from policy noise, so the conditions below share their shuffles and the whole file reproduces exactly.

Regenerate with `python3 tune.py report`.

## Does the gauntlet separate skill levels?

`reckless` is a control, not a skill level: it never gives up a bout.

| condition | mean depth | clears | wiped at the first | health left |
|---|---|---|---|---|
| sharp | 5.48 | 48% | 5% | 4.4 |
| typical | 3.82 | 24% | 15% | 2.7 |
| tired | 0.84 | 0% | 55% | 0.3 |
| reckless | 4.76 | 34% | 6% | 3.3 |

## Where runs actually end

| depth | opponent | reached (sharp) | win rate (sharp) | reached (typical) | win rate (typical) | lost to wounds (typical) |
|---|---|---|---|---|---|---|
| 1 | The Ferryman | 600 | 95% | 600 | 85% | 57% |
| 2 | Grandmother | 569 | 96% | 512 | 89% | 67% |
| 3 | The Tax Collector | 548 | 86% | 458 | 72% | 39% |
| 4 | Two Coats | 470 | 86% | 332 | 79% | 46% |
| 5 | The Winter Soldier | 406 | 89% | 263 | 85% | 48% |
| 6 | The Cardsharp | 361 | 92% | 223 | 87% | 30% |
| 7 | The Magistrate | 332 | 95% | 193 | 89% | 33% |
| 8 | The Fool Himself | 315 | 91% | 172 | 82% | 16% |

## Relic power, granted from the start

Baseline is a typical player with no relics: mean depth 3.82, 24% clears.

| relic | mean depth | clears | delta | text |
|---|---|---|---|---|
| Deflection | 5.22 | 40% | +1.39 | Pass an attack back by playing a card of the same rank. |
| Hoard | 4.84 | 35% | +1.02 | You refill to seven cards instead of six. |
| Quartermaster | 4.57 | 32% | +0.75 | Whenever you pick up, burn your worst card. |
| Reversal | 4.37 | 30% | +0.54 | When you pick up, the cards you already beat are burned instead. |
| Whetstone | 4.27 | 29% | +0.44 | Your sixes beat any card of their own suit. |
| Ironbound | 4.17 | 28% | +0.34 | Trump cards you pick up cost you nothing. |
| Duelist | 4.09 | 27% | +0.27 | They may attack you with at most four cards in a bout. |
| Field Surgeon | 3.99 | 27% | +0.17 | Survive a bout of three or more cards and mend one wound. |
| Banner | 3.94 | 26% | +0.12 | You name the trump suit at the start of every encounter. |
| Ace in the Hole | 3.94 | 26% | +0.12 | Your aces beat anything. |

## Shopping policies

| archetype | mean depth | clears | wiped at the first |
|---|---|---|---|
| balanced | 3.82 | 24% | 15% |
| relic_hunter | 3.45 | 18% | 15% |
| thinner | 3.37 | 15% | 15% |
| high_roller | 3.19 | 11% | 15% |
| trump_stack | 3.46 | 17% | 15% |

## Does health bind?

Ironbound exists only to blunt wounds, so its value is a direct readout of whether the wound system is doing anything.

| starting health | mean depth | clears | wiped at the first | health left | Ironbound is worth |
|---|---|---|---|---|---|
| 4 | 1.88 | 6% | 35% | 0.3 | +0.82 |
| 6 | 3.05 | 15% | 20% | 1.2 | +0.68 |
| 8 | 3.82 | 24% | 15% | 2.7 | +0.34 |
| 10 | 4.29 | 29% | 12% | 4.5 | +0.20 |
| 12 | 4.31 | 31% | 11% | 5.7 | -0.02 |
| 16 | 4.33 | 31% | 11% | 8.5 | -0.07 |
| 20 | 4.36 | 33% | 11% | 12.0 | -0.09 |
| 30 | 4.17 | 29% | 11% | 20.7 | -0.05 |

