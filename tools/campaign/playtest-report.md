# Campaign playtest, imperfect solver

**CONTROL: 93/100 levels solved with a perfect eye** (sigma 0, k 0, t 0, no misclicks, strategy `reason`).


7 levels are missed. All but 3 of them are **proved** unfair below: a second arrangement exists that uses exactly the bank swatches, keeps every given cell, and shows every run as an even walk to within the app's own sameness threshold, so no eye and no amount of thought can choose between it and the authored answer. Any level missed *without* such a proof is a suspected strategy bug and is named as one.


5 levels carry that proof in total; the other 1 are ones where the alternative is even to within delta-E 2 but very slightly less even than the authored answer, so a literally perfect eye still picks the intended board while a human eye could not.

| # | name | chapter | bank | unpinned runs | control | verdict |
|---|---|---|---|---|---|---|
| 36 | Rocket | Everyday Things | 10 | 2 | 17% | swap (5, 1) with (5, 3): both sit only on runs that stay even walks afterwards, and neither run's step stands out |
| 47 | Anchor | Everyday Things | 13 | 3 | 52% | run 2 reversed: 4 cells change, first at (6, 0) |
| 66 | Spider | Creatures | 16 | 4 | 47% | swap (1, 6) with (3, 6): both sit only on runs that stay even walks afterwards, and neither run's step stands out |
| 67 | Butterfly | Creatures | 14 | 3 | 0% | UNEXPLAINED, suspect strategy |
| 68 | Snake | Creatures | 19 | 3 | 0% | UNEXPLAINED, suspect strategy |
| 74 | Castle | Landmarks | 18 | 5 | 52% | run 4 reversed: 6 cells change, first at (1, 0) |
| 78 | Fountain | Landmarks | 23 | 4 | 0% | UNEXPLAINED, suspect strategy |


Every difficulty number below is therefore reported over the 95 levels with a unique reasoned answer. The 5 unfair levels are excluded from the rankings, the chapter averages and the correlations, because their failure rate measures a coin, not a player.


100 levels, 60 trials per level per condition, 6 conditions, strategy `reason` (36,000 simulated playthroughs). Every trial is seeded from the level index and the trial number alone, so conditions share their random draws and the whole file reproduces exactly.


## The levels that fail hardest

Fair levels only, ranked by mean success across the played conditions. `sep` is the closest approach between two runs' colours, `step` the smallest step along a run, `margin` the closest pair in the bank.

| # | name | chapter | bank | sep | step | margin | mean | sharp | typical | tired | k=0.5 | fumbles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 68 | Snake | Creatures | 19 | 5.1 | 5.3 | 5.2 | 0% | 0% | 0% | 0% | 0% | 0% |
| 97 | Citadel | Mastery | 29 | 4.7 | 4.7 | 4.7 | 0% | 0% | 0% | 0% | 0% | 0% |
| 67 | Butterfly | Creatures | 14 | 10.0 | 7.3 | 7.3 | 0% | 0% | 0% | 0% | 0% | 2% |
| 90 | Circuit | Mastery | 22 | 8.1 | 5.7 | 5.7 | 1% | 3% | 0% | 0% | 0% | 0% |
| 94 | Palace | Mastery | 27 | 4.8 | 4.8 | 4.8 | 1% | 7% | 0% | 0% | 0% | 0% |
| 85 | Harbor | Landmarks | 20 | 6.6 | 5.2 | 5.2 | 2% | 7% | 2% | 0% | 0% | 0% |
| 75 | Church | Landmarks | 19 | 5.8 | 4.9 | 4.9 | 2% | 8% | 2% | 0% | 0% | 0% |
| 78 | Fountain | Landmarks | 23 | 8.0 | 5.3 | 5.9 | 4% | 18% | 0% | 0% | 0% | 0% |
| 84 | Garden | Landmarks | 22 | 8.3 | 4.6 | 4.6 | 4% | 7% | 3% | 0% | 3% | 5% |
| 95 | Carousel | Mastery | 28 | 4.3 | 4.4 | 4.3 | 4% | 13% | 3% | 0% | 2% | 2% |
| 77 | Pyramid | Landmarks | 19 | 11.2 | 6.5 | 6.5 | 5% | 23% | 2% | 0% | 0% | 2% |
| 96 | Organ | Mastery | 28 | 4.9 | 4.7 | 4.7 | 6% | 23% | 3% | 0% | 2% | 0% |
| 83 | Observatory | Landmarks | 22 | 8.9 | 6.0 | 6.0 | 7% | 28% | 0% | 2% | 2% | 2% |
| 89 | Cascade | Mastery | 16 | 6.4 | 4.5 | 4.5 | 8% | 33% | 2% | 0% | 0% | 3% |
| 100 | Mandala | Mastery | 30 | 5.7 | 4.0 | 4.0 | 8% | 42% | 0% | 0% | 0% | 0% |
| 81 | Ferris | Landmarks | 22 | 9.2 | 7.1 | 7.2 | 11% | 42% | 3% | 0% | 3% | 5% |
| 86 | Waterfall | Landmarks | 24 | 8.5 | 5.8 | 5.8 | 11% | 35% | 7% | 2% | 0% | 10% |
| 70 | Fox | Creatures | 15 | 6.7 | 7.2 | 6.7 | 14% | 52% | 10% | 2% | 0% | 7% |
| 80 | Cathedral | Landmarks | 21 | 10.2 | 6.7 | 6.7 | 15% | 42% | 13% | 5% | 5% | 12% |
| 73 | Sailboat | Landmarks | 16 | 9.5 | 7.3 | 7.3 | 17% | 58% | 12% | 3% | 10% | 3% |


## Where the difficulty comes from, at `typical eye`

sigma=2 k=0 t=1.5 misclick=0, worst first, with the three channel measurements and the mean number of decisions the player was forced to guess on.

| # | name | bank | sep | sep/sigma | step | step/sigma | margin | success | wrong | coin flips |
|---|---|---|---|---|---|---|---|---|---|---|
| 67 | Butterfly | 14 | 10.0 | 5.0 | 7.3 | 3.6 | 7.3 | 0% | 9.25 | 2.12 |
| 68 | Snake | 19 | 5.1 | 2.5 | 5.3 | 2.6 | 5.2 | 0% | 15.67 | 4.57 |
| 78 | Fountain | 23 | 8.0 | 4.0 | 5.3 | 2.7 | 5.9 | 0% | 12.00 | 3.28 |
| 83 | Observatory | 22 | 8.9 | 4.4 | 6.0 | 3.0 | 6.0 | 0% | 11.52 | 3.20 |
| 90 | Circuit | 22 | 8.1 | 4.1 | 5.7 | 2.9 | 5.7 | 0% | 16.13 | 4.63 |
| 94 | Palace | 27 | 4.8 | 2.4 | 4.8 | 2.4 | 4.8 | 0% | 19.53 | 6.03 |
| 97 | Citadel | 29 | 4.7 | 2.4 | 4.7 | 2.3 | 4.7 | 0% | 27.32 | 8.58 |
| 100 | Mandala | 30 | 5.7 | 2.9 | 4.0 | 2.0 | 4.0 | 0% | 10.65 | 8.67 |
| 75 | Church | 19 | 5.8 | 2.9 | 4.9 | 2.4 | 4.9 | 2% | 12.45 | 4.92 |
| 77 | Pyramid | 19 | 11.2 | 5.6 | 6.5 | 3.2 | 6.5 | 2% | 11.40 | 3.32 |
| 85 | Harbor | 20 | 6.6 | 3.3 | 5.2 | 2.6 | 5.2 | 2% | 14.23 | 4.40 |
| 89 | Cascade | 16 | 6.4 | 3.2 | 4.5 | 2.3 | 4.5 | 2% | 9.12 | 4.03 |
| 81 | Ferris | 22 | 9.2 | 4.6 | 7.1 | 3.5 | 7.2 | 3% | 14.87 | 4.42 |
| 84 | Garden | 22 | 8.3 | 4.1 | 4.6 | 2.3 | 4.6 | 3% | 15.03 | 4.07 |
| 95 | Carousel | 28 | 4.3 | 2.2 | 4.4 | 2.2 | 4.3 | 3% | 6.70 | 3.50 |
| 96 | Organ | 28 | 4.9 | 2.4 | 4.7 | 2.3 | 4.7 | 3% | 11.40 | 4.25 |
| 86 | Waterfall | 24 | 8.5 | 4.3 | 5.8 | 2.9 | 5.8 | 7% | 5.97 | 2.27 |
| 70 | Fox | 15 | 6.7 | 3.3 | 7.2 | 3.6 | 6.7 | 10% | 6.67 | 2.50 |
| 99 | Vault | 30 | 6.1 | 3.1 | 4.2 | 2.1 | 4.2 | 10% | 4.88 | 3.73 |
| 69 | Penguin | 17 | 7.3 | 3.6 | 6.6 | 3.3 | 6.6 | 12% | 5.65 | 1.42 |


## Per chapter

Mean success by chapter over fair levels, chapters in play order, so the columns should fall smoothly. A cliff is a pacing bug. `unfair` counts the levels excluded as provably ambiguous.

| chapter | levels | unfair | mean sep | mean step | control | sharp | typical | tired | k=0.5 | fumbles |
|---|---|---|---|---|---|---|---|---|---|---|
| First Steps | 1-6 | 0 | 99.0 | 12.8 | 100% | 100% | 100% | 100% | 100% | 99% |
| Two Strokes | 7-18 | 0 | 14.1 | 10.3 | 100% | 100% | 100% | 96% | 98% | 95% |
| Crossings | 19-32 | 0 | 11.3 | 8.1 | 100% | 100% | 97% | 86% | 92% | 87% |
| Everyday Things | 33-52 | 2 | 9.2 | 7.0 | 100% | 98% | 84% | 57% | 69% | 67% |
| Creatures | 53-70 | 2 | 7.9 | 7.3 | 88% | 76% | 51% | 27% | 40% | 40% |
| Landmarks | 71-88 | 1 | 8.0 | 5.7 | 94% | 52% | 20% | 4% | 5% | 13% |
| Mastery | 89-100 | 0 | 5.7 | 4.6 | 100% | 48% | 9% | 1% | 1% | 4% |


## Which measurement predicts failure?

Correlation with success rate at `typical eye` over the 95 fair levels. Positive means more of the quantity is an easier level, so the channel measurements should come out positive and `unpinned runs` negative.

| quantity | Pearson r | Spearman rho |
|---|---|---|
| between-run separation | +0.314 | +0.666 |
| within-run step | +0.596 | +0.748 |
| unpinned runs (count) | -0.658 | -0.658 |
| hardest bank margin | +0.272 | +0.769 |
| bank size | -0.802 | -0.842 |


Bank size is in the table as a confound check: late levels have both tighter colours and more decisions, so a channel measurement only earns its keep if it beats plain counting. Success is a whole-board test, so it punishes size twice over (thirty decisions at 99% each still lose a quarter of the time). The table below removes that by asking the same question per cell.

| quantity | Pearson r vs per-cell error | Spearman rho |
|---|---|---|
| between-run separation | -0.235 | -0.629 |
| within-run step | -0.451 | -0.682 |
| unpinned runs (count) | +0.833 | +0.705 |
| hardest bank margin | -0.203 | -0.705 |
| bank size | +0.589 | +0.776 |


Negative is what a difficulty measurement should be here: more separation, fewer errors. Note that `within-run step` and `hardest bank margin` are the same number on 64 of the 95 fair levels, because the closest pair in the bank is almost always two neighbours on one run. The step is the more useful of the two to author against, since it is the quantity the generator can set directly.


Banded by between-run separation against the perceptual noise:

| band | levels | mean success | mean wrong cells |
|---|---|---|---|
| 2 to 3 sigma (strained) | 11 | 17% | 10.40 |
| 3 to 5 sigma (workable) | 47 | 54% | 3.53 |
| over 5 sigma (comfortable) | 37 | 86% | 0.96 |


Banded by within-run step against the perceptual noise:

| band | levels | mean success | mean wrong cells |
|---|---|---|---|
| under 2 sigma (coin flip) | 1 | 0% | 10.65 |
| 2 to 3 sigma (strained) | 26 | 22% | 8.19 |
| 3 to 5 sigma (workable) | 59 | 75% | 1.57 |
| over 5 sigma (comfortable) | 9 | 100% | 0.00 |


## Settings used

| condition | sigma | k | t | misclick | mean success (fair) | fair levels above 90% |
|---|---|---|---|---|---|---|
| noise-free control | 0 | 0 | 0 | 0 | 97% | 92 |
| sharp eye | 1 | 0 | 1.5 | 0 | 80% | 64 |
| typical eye | 2 | 0 | 1.5 | 0 | 62% | 46 |
| tired eye | 3 | 0 | 1.5 | 0 | 47% | 24 |
| compressed 50% | 1 | 0.5 | 1.5 | 0 | 53% | 31 |
| typical eye + fumbles | 2 | 0 | 1.5 | 0.02 | 53% | 23 |


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

