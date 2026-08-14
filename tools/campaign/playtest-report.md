# Campaign playtest, imperfect solver

**CONTROL: 194/200 levels solved with a perfect eye** (sigma 0, k 0, t 0, no misclicks, strategy `reason`).


6 levels are missed. All but 3 of them are **proved** unfair below: a second arrangement exists that uses exactly the bank swatches, keeps every given cell, and shows every run as an even walk to within the app's own sameness threshold, so no eye and no amount of thought can choose between it and the authored answer. Any level missed *without* such a proof is a suspected strategy bug and is named as one.


4 levels carry that proof in total; the other 1 are ones where the alternative is even to within delta-E 2 but very slightly less even than the authored answer, so a literally perfect eye still picks the intended board while a human eye could not.

| # | name | chapter | bank | unpinned runs | control | verdict |
|---|---|---|---|---|---|---|
| 36 | Rocket | Everyday Things | 10 | 2 | 17% | swap (5, 1) with (5, 3): both sit only on runs that stay even walks afterwards, and neither run's step stands out |
| 66 | Spider | Creatures | 16 | 4 | 53% | swap (1, 6) with (3, 6): both sit only on runs that stay even walks afterwards, and neither run's step stands out |
| 67 | Butterfly | Creatures | 14 | 3 | 0% | UNEXPLAINED, suspect strategy |
| 74 | Castle | Landmarks | 18 | 5 | 52% | run 4 reversed: 6 cells change, first at (1, 0) |
| 85 | Harbor | Landmarks | 20 | 1 | 0% | UNEXPLAINED, suspect strategy |
| 97 | Citadel | Mastery | 29 | 6 | 0% | UNEXPLAINED, suspect strategy |


Every difficulty number below is therefore reported over the 196 levels with a unique reasoned answer. The 4 unfair levels are excluded from the rankings, the chapter averages and the correlations, because their failure rate measures a coin, not a player.


200 levels, 60 trials per level per condition, 6 conditions, strategy `reason` (72,000 simulated playthroughs). Every trial is seeded from the level index and the trial number alone, so conditions share their random draws and the whole file reproduces exactly.


## The levels that fail hardest

Fair levels only, ranked by mean success across the played conditions. `sep` is the closest approach between two runs' colours, `step` the smallest step along a run, `margin` the closest pair in the bank.

| # | name | chapter | bank | sep | step | margin | mean | sharp | typical | tired | k=0.5 | fumbles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 67 | Butterfly | Creatures | 14 | 9.9 | 7.3 | 7.3 | 0% | 0% | 0% | 0% | 0% | 0% |
| 97 | Citadel | Mastery | 29 | 5.7 | 4.3 | 4.6 | 0% | 0% | 0% | 0% | 0% | 0% |
| 94 | Palace | Mastery | 27 | 4.3 | 4.3 | 4.3 | 0% | 2% | 0% | 0% | 0% | 0% |
| 85 | Harbor | Landmarks | 20 | 7.4 | 5.1 | 5.1 | 1% | 3% | 0% | 0% | 0% | 0% |
| 90 | Circuit | Mastery | 22 | 8.1 | 5.7 | 5.7 | 1% | 3% | 0% | 0% | 0% | 0% |
| 75 | Church | Landmarks | 19 | 5.8 | 4.9 | 4.9 | 2% | 10% | 2% | 0% | 0% | 0% |
| 84 | Garden | Landmarks | 22 | 8.3 | 4.6 | 4.6 | 3% | 5% | 3% | 0% | 3% | 5% |
| 68 | Snake | Creatures | 19 | 8.6 | 5.0 | 5.0 | 4% | 17% | 0% | 0% | 2% | 0% |
| 78 | Fountain | Landmarks | 23 | 8.0 | 5.3 | 5.9 | 4% | 18% | 0% | 0% | 0% | 0% |
| 95 | Carousel | Mastery | 28 | 4.3 | 4.4 | 4.3 | 4% | 13% | 3% | 0% | 0% | 2% |
| 77 | Pyramid | Landmarks | 19 | 11.1 | 6.5 | 6.5 | 5% | 23% | 2% | 0% | 0% | 2% |
| 96 | Organ | Mastery | 28 | 4.8 | 4.6 | 4.6 | 6% | 23% | 3% | 0% | 2% | 2% |
| 83 | Observatory | Landmarks | 22 | 8.9 | 6.0 | 6.0 | 7% | 28% | 0% | 2% | 2% | 2% |
| 89 | Cascade | Mastery | 16 | 6.4 | 4.5 | 4.5 | 8% | 33% | 2% | 0% | 0% | 3% |
| 100 | Mandala | Mastery | 30 | 5.8 | 4.0 | 4.0 | 8% | 42% | 0% | 0% | 0% | 0% |
| 81 | Ferris | Landmarks | 22 | 9.2 | 6.7 | 6.7 | 10% | 42% | 3% | 0% | 2% | 3% |
| 86 | Waterfall | Landmarks | 24 | 8.5 | 5.8 | 5.8 | 11% | 35% | 8% | 2% | 0% | 10% |
| 70 | Fox | Creatures | 15 | 6.5 | 7.2 | 6.5 | 15% | 55% | 10% | 2% | 0% | 7% |
| 80 | Cathedral | Landmarks | 21 | 10.2 | 6.7 | 6.7 | 15% | 42% | 13% | 5% | 3% | 12% |
| 177 | Banister | Interiors | 23 | 4.1 | 4.4 | 4.4 | 17% | 63% | 17% | 2% | 0% | 5% |


## Where the difficulty comes from, at `typical eye`

sigma=2 k=0 t=1.5 misclick=0, worst first, with the three channel measurements and the mean number of decisions the player was forced to guess on.

| # | name | bank | sep | sep/sigma | step | step/sigma | margin | success | wrong | coin flips |
|---|---|---|---|---|---|---|---|---|---|---|
| 67 | Butterfly | 14 | 9.9 | 5.0 | 7.3 | 3.6 | 7.3 | 0% | 9.27 | 2.25 |
| 68 | Snake | 19 | 8.6 | 4.3 | 5.0 | 2.5 | 5.0 | 0% | 11.38 | 2.92 |
| 78 | Fountain | 23 | 8.0 | 4.0 | 5.3 | 2.7 | 5.9 | 0% | 12.03 | 3.27 |
| 83 | Observatory | 22 | 8.9 | 4.4 | 6.0 | 3.0 | 6.0 | 0% | 11.68 | 3.28 |
| 85 | Harbor | 20 | 7.4 | 3.7 | 5.1 | 2.6 | 5.1 | 0% | 13.53 | 4.53 |
| 90 | Circuit | 22 | 8.1 | 4.1 | 5.7 | 2.9 | 5.7 | 0% | 16.20 | 4.58 |
| 94 | Palace | 27 | 4.3 | 2.1 | 4.3 | 2.1 | 4.3 | 0% | 21.18 | 6.53 |
| 97 | Citadel | 29 | 5.7 | 2.8 | 4.3 | 2.1 | 4.6 | 0% | 27.35 | 8.88 |
| 100 | Mandala | 30 | 5.8 | 2.9 | 4.0 | 2.0 | 4.0 | 0% | 10.28 | 8.48 |
| 75 | Church | 19 | 5.8 | 2.9 | 4.9 | 2.4 | 4.9 | 2% | 12.83 | 5.10 |
| 77 | Pyramid | 19 | 11.1 | 5.6 | 6.5 | 3.2 | 6.5 | 2% | 11.37 | 3.23 |
| 89 | Cascade | 16 | 6.4 | 3.2 | 4.5 | 2.3 | 4.5 | 2% | 9.10 | 4.05 |
| 81 | Ferris | 22 | 9.2 | 4.6 | 6.7 | 3.4 | 6.7 | 3% | 14.90 | 4.25 |
| 84 | Garden | 22 | 8.3 | 4.1 | 4.6 | 2.3 | 4.6 | 3% | 15.13 | 4.27 |
| 95 | Carousel | 28 | 4.3 | 2.1 | 4.4 | 2.2 | 4.3 | 3% | 6.70 | 3.52 |
| 96 | Organ | 28 | 4.8 | 2.4 | 4.6 | 2.3 | 4.6 | 3% | 11.27 | 4.13 |
| 86 | Waterfall | 24 | 8.5 | 4.3 | 5.8 | 2.9 | 5.8 | 8% | 5.78 | 2.27 |
| 92 | Lattice | 27 | 6.7 | 3.3 | 4.5 | 2.3 | 4.5 | 8% | 5.92 | 5.80 |
| 192 | Telescope | 24 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 8% | 4.12 | 3.75 |
| 200 | Ironworks | 23 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 8% | 4.35 | 3.08 |


## Per chapter

Mean success by chapter over fair levels, chapters in play order. Difficulty intentionally follows a sawtooth: it can peak at a chapter's end, ease at the next chapter's opening, then build again. `unfair` counts levels excluded as provably ambiguous.

| chapter | levels | unfair | mean sep | mean step | control | sharp | typical | tired | k=0.5 | fumbles |
|---|---|---|---|---|---|---|---|---|---|---|
| First Steps | 1-6 | 0 | 99.0 | 12.8 | 100% | 100% | 100% | 100% | 100% | 99% |
| Two Strokes | 7-18 | 0 | 13.5 | 9.9 | 100% | 100% | 100% | 96% | 98% | 95% |
| Crossings | 19-32 | 0 | 11.5 | 8.0 | 100% | 100% | 98% | 86% | 93% | 87% |
| Everyday Things | 33-52 | 1 | 9.4 | 6.8 | 100% | 98% | 83% | 54% | 67% | 66% |
| Creatures | 53-70 | 2 | 8.2 | 7.3 | 94% | 78% | 53% | 29% | 40% | 43% |
| Landmarks | 71-88 | 1 | 8.0 | 5.7 | 94% | 52% | 19% | 4% | 5% | 13% |
| Mastery | 89-100 | 0 | 5.8 | 4.5 | 92% | 47% | 7% | 0% | 0% | 4% |
| Workshop | 101-120 | 0 | 5.1 | 4.8 | 100% | 96% | 47% | 11% | 9% | 37% |
| Orchestra | 121-140 | 0 | 5.2 | 4.9 | 100% | 94% | 39% | 7% | 6% | 28% |
| Circuitry | 141-160 | 0 | 4.9 | 4.5 | 100% | 94% | 34% | 5% | 3% | 23% |
| Interiors | 161-180 | 0 | 4.7 | 4.4 | 100% | 93% | 26% | 3% | 2% | 18% |
| Grand Works | 181-200 | 0 | 4.5 | 4.4 | 100% | 92% | 20% | 2% | 1% | 14% |


## Which measurement predicts failure?

Correlation with success rate at `typical eye` over the 196 fair levels. Positive means more of the quantity is an easier level, so the channel measurements should come out positive and `unpinned runs` negative.

| quantity | Pearson r | Spearman rho |
|---|---|---|
| between-run separation | +0.390 | +0.567 |
| within-run step | +0.679 | +0.641 |
| unpinned runs (count) | -0.389 | -0.435 |
| hardest bank margin | +0.337 | +0.641 |
| bank size | -0.824 | -0.773 |


Bank size is in the table as a confound check: late levels have both tighter colours and more decisions, so a channel measurement only earns its keep if it beats plain counting. Success is a whole-board test, so it punishes size twice over (thirty decisions at 99% each still lose a quarter of the time). The table below removes that by asking the same question per cell.

| quantity | Pearson r vs per-cell error | Spearman rho |
|---|---|---|
| between-run separation | -0.185 | -0.493 |
| within-run step | -0.289 | -0.548 |
| unpinned runs (count) | +0.820 | +0.519 |
| hardest bank margin | -0.169 | -0.546 |
| bank size | +0.444 | +0.632 |


Negative is what a difficulty measurement should be here: more separation, fewer errors. Note that `within-run step` and `hardest bank margin` are the same number on 161 of the 196 fair levels, because the closest pair in the bank is almost always two neighbours on one run. The step is the more useful of the two to author against, since it is the quantity the generator can set directly.


Banded by between-run separation against the perceptual noise:

| band | levels | mean success | mean wrong cells |
|---|---|---|---|
| under 2 sigma (coin flip) | 1 | 23% | 3.30 |
| 2 to 3 sigma (strained) | 100 | 31% | 3.34 |
| 3 to 5 sigma (workable) | 58 | 50% | 3.54 |
| over 5 sigma (comfortable) | 37 | 88% | 0.73 |


Banded by within-run step against the perceptual noise:

| band | levels | mean success | mean wrong cells |
|---|---|---|---|
| under 2 sigma (coin flip) | 1 | 23% | 3.30 |
| 2 to 3 sigma (strained) | 129 | 32% | 3.69 |
| 3 to 5 sigma (workable) | 56 | 75% | 1.62 |
| over 5 sigma (comfortable) | 10 | 100% | 0.00 |


## Settings used

| condition | sigma | k | t | misclick | mean success (fair) | fair levels above 90% |
|---|---|---|---|---|---|---|
| noise-free control | 0 | 0 | 0 | 0 | 98% | 193 |
| sharp eye | 1 | 0 | 1.5 | 0 | 87% | 149 |
| typical eye | 2 | 0 | 1.5 | 0 | 48% | 46 |
| tired eye | 3 | 0 | 1.5 | 0 | 26% | 23 |
| compressed 50% | 1 | 0.5 | 1.5 | 0 | 28% | 30 |
| typical eye + fumbles | 2 | 0 | 1.5 | 0.02 | 39% | 23 |


Parameter meanings, all in delta-E units scaled x100 as in `oklch.dist` (one JND is about 2):

- `sigma`: total perceptual error per reading, split so that 35% of the variance is a standing bias per colour (identical every time that colour is read) and the rest is fresh jitter.
- `k`: similarity compression toward the board mean in OKLab, which scales every board delta-E by exactly (1 - k), as TestingFilter does in the app.
- `t`: decision margin below which the player cannot tell the winner from the runner-up and picks at random among the tied candidates.
- `misclick`: chance a drag lands in a different empty cell, preferring one adjacent to the intended cell.


## What this model does not capture

- The `reason` player never backtracks across runs. Once a run is laid down it stays down, so a partition mistake early on cannot be undone by noticing that a later run has become unfillable. A determined person would notice.
- Partition is done implicitly, by scoring the ramp a hypothesis implies against the swatches still in the bank. That is weaker than a person eyeing the whole pile and spotting three colour families at once, and it is where the model most likely understates a careful player.
- Elimination is only used at the very end, when a run is down to one hole. Counting arguments in the middle of a board (this family has five members and that run has five holes) are not modelled.
- Hue steps above 180 degrees between the anchors on hand are read as the shorter rotation, because nothing on the board disambiguates them.
- Compression is applied in OKLab, so at k > 0 an evenly stepped LCh ramp is no longer evenly stepped in the space the player fits. The compressed condition therefore mixes reduced discriminability with a genuine model bias, and its absolute numbers should be read as a direction rather than a measurement.
- sigma, t and the bias share are asserted, not measured against humans. Only their ordering is trustworthy.
- The two strategies are not given the same number of looks, and it flatters the careless one. `reason` reads every colour once and then reasons on those readings, while `match` re-reads on every comparison and so averages part of its own jitter away. Letting `reason` read each colour two or three times instead moves it from 64% to 69% and 71% at `typical eye`, against 65% for `match`, so the careful player's real advantage under noise is around five points and the sweep below shows none of it. The zero-noise control, where reading twice changes nothing, is the honest comparison: 100% against 89%.

