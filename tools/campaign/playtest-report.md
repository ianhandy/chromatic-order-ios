# Campaign playtest, imperfect solver

**CONTROL: 200/200 levels solved with a perfect eye** (sigma 0, k 0, t 0, no misclicks, strategy `reason`).


200 levels, 60 trials per level per condition, 6 conditions, strategy `reason` (72,000 simulated playthroughs). Every trial is seeded from the level index and the trial number alone, so conditions share their random draws and the whole file reproduces exactly.


## The levels that fail hardest

Fair levels only, ranked by mean success across the played conditions. `sep` is the closest approach between two runs' colours, `step` the smallest step along a run, `margin` the closest pair in the bank.

| # | name | chapter | bank | sep | step | margin | mean | sharp | typical | tired | k=0.5 | fumbles |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 197 | Kiln | The Limit | 24 | 4.4 | 4.4 | 4.4 | 19% | 68% | 17% | 0% | 0% | 10% |
| 177 | Banister | Sections | 24 | 4.1 | 4.4 | 4.4 | 21% | 68% | 20% | 3% | 0% | 12% |
| 200 | Ironworks | The Limit | 23 | 4.2 | 4.2 | 4.2 | 21% | 88% | 8% | 2% | 0% | 7% |
| 179 | Stove | Sections | 19 | 4.1 | 4.1 | 4.1 | 21% | 87% | 10% | 2% | 0% | 8% |
| 147 | Plug | Networks | 19 | 4.7 | 4.7 | 4.7 | 22% | 70% | 23% | 2% | 0% | 13% |
| 195 | Powerhouse | The Limit | 25 | 4.2 | 4.2 | 4.2 | 22% | 87% | 12% | 0% | 0% | 10% |
| 198 | Breakwater | The Limit | 23 | 4.4 | 4.4 | 4.4 | 22% | 90% | 12% | 0% | 0% | 8% |
| 180 | Dome | Sections | 22 | 4.0 | 4.0 | 4.0 | 23% | 95% | 12% | 0% | 0% | 8% |
| 192 | Telescope | The Limit | 24 | 4.2 | 4.2 | 4.2 | 23% | 92% | 8% | 3% | 0% | 12% |
| 193 | Smelter | The Limit | 24 | 4.0 | 4.0 | 4.0 | 23% | 95% | 15% | 0% | 0% | 7% |
| 184 | Water Tower | The Limit | 20 | 4.2 | 4.2 | 4.2 | 24% | 92% | 17% | 3% | 0% | 8% |
| 199 | Scaffold | The Limit | 27 | 4.6 | 4.6 | 4.6 | 24% | 97% | 13% | 0% | 0% | 12% |
| 196 | Engine Shed | The Limit | 29 | 4.7 | 4.7 | 4.7 | 25% | 93% | 20% | 0% | 0% | 13% |
| 160 | Motherboard | Networks | 22 | 4.5 | 4.5 | 4.5 | 26% | 93% | 25% | 0% | 0% | 10% |
| 128 | Microphone | Many Runs | 18 | 5.4 | 5.4 | 5.4 | 26% | 78% | 28% | 2% | 2% | 20% |
| 186 | Gantry | The Limit | 21 | 4.2 | 4.2 | 4.2 | 26% | 92% | 23% | 2% | 2% | 12% |
| 191 | Terminal | The Limit | 23 | 4.5 | 4.5 | 4.5 | 26% | 95% | 17% | 2% | 7% | 10% |
| 194 | Derrick | The Limit | 22 | 4.0 | 4.0 | 4.0 | 26% | 90% | 23% | 2% | 0% | 15% |
| 171 | Skylight | Sections | 19 | 4.2 | 4.2 | 4.2 | 26% | 87% | 28% | 2% | 0% | 15% |
| 175 | Curtain | Sections | 22 | 4.6 | 4.6 | 4.6 | 26% | 98% | 20% | 2% | 0% | 12% |


## Where the difficulty comes from, at `typical eye`

sigma=2 k=0 t=1.5 misclick=0, worst first, with the three channel measurements and the mean number of decisions the player was forced to guess on.

| # | name | bank | sep | sep/sigma | step | step/sigma | margin | success | wrong | coin flips |
|---|---|---|---|---|---|---|---|---|---|---|
| 192 | Telescope | 24 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 8% | 4.12 | 3.75 |
| 200 | Ironworks | 23 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 8% | 4.35 | 3.08 |
| 179 | Stove | 19 | 4.1 | 2.0 | 4.1 | 2.0 | 4.1 | 10% | 3.93 | 3.62 |
| 180 | Dome | 22 | 4.0 | 2.0 | 4.0 | 2.0 | 4.0 | 12% | 3.73 | 3.40 |
| 195 | Powerhouse | 25 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 12% | 3.53 | 3.23 |
| 198 | Breakwater | 23 | 4.4 | 2.2 | 4.4 | 2.2 | 4.4 | 12% | 4.33 | 3.97 |
| 199 | Scaffold | 27 | 4.6 | 2.3 | 4.6 | 2.3 | 4.6 | 13% | 4.55 | 3.58 |
| 193 | Smelter | 24 | 4.0 | 2.0 | 4.0 | 2.0 | 4.0 | 15% | 3.78 | 3.77 |
| 184 | Water Tower | 20 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 17% | 3.73 | 2.87 |
| 191 | Terminal | 23 | 4.5 | 2.3 | 4.5 | 2.3 | 4.5 | 17% | 2.98 | 1.95 |
| 197 | Kiln | 24 | 4.4 | 2.2 | 4.4 | 2.2 | 4.4 | 17% | 3.78 | 2.70 |
| 168 | Chandelier | 20 | 4.3 | 2.2 | 4.3 | 2.2 | 4.3 | 18% | 2.95 | 1.98 |
| 175 | Curtain | 22 | 4.6 | 2.3 | 4.6 | 2.3 | 4.6 | 20% | 3.40 | 3.12 |
| 177 | Banister | 24 | 4.1 | 2.0 | 4.4 | 2.2 | 4.4 | 20% | 3.92 | 2.45 |
| 196 | Engine Shed | 29 | 4.7 | 2.3 | 4.7 | 2.3 | 4.7 | 20% | 3.72 | 3.03 |
| 153 | Radar Dish | 20 | 4.4 | 2.2 | 4.4 | 2.2 | 4.4 | 22% | 3.13 | 2.85 |
| 159 | Oscilloscope | 26 | 4.6 | 2.3 | 4.6 | 2.3 | 4.6 | 22% | 3.30 | 3.15 |
| 176 | Elevator | 23 | 4.5 | 2.3 | 4.5 | 2.3 | 4.5 | 22% | 3.35 | 3.00 |
| 178 | Landing | 18 | 4.6 | 2.3 | 4.2 | 2.1 | 4.2 | 22% | 3.13 | 2.53 |
| 182 | Dam | 19 | 4.2 | 2.1 | 4.2 | 2.1 | 4.2 | 22% | 2.93 | 2.43 |


## Per chapter

Mean success by chapter over fair levels, chapters in play order. Difficulty intentionally follows a sawtooth: it can peak at a chapter's end, ease at the next chapter's opening, then build again. `unfair` counts levels excluded as provably ambiguous.

| chapter | levels | unfair | mean sep | mean step | control | sharp | typical | tired | k=0.5 | fumbles |
|---|---|---|---|---|---|---|---|---|---|---|
| First Steps | 1-6 | 0 | 99.0 | 12.8 | 100% | 100% | 100% | 100% | 100% | 99% |
| Two Runs | 7-18 | 0 | 13.5 | 9.9 | 100% | 100% | 100% | 96% | 98% | 95% |
| Crossings | 19-32 | 0 | 11.5 | 8.0 | 100% | 98% | 96% | 85% | 95% | 86% |
| Wider Boards | 33-52 | 0 | 8.7 | 6.7 | 100% | 100% | 89% | 60% | 71% | 73% |
| Chroma | 53-70 | 0 | 8.0 | 7.0 | 100% | 96% | 75% | 44% | 59% | 60% |
| Long Ramps | 71-88 | 0 | 7.7 | 5.4 | 100% | 96% | 63% | 26% | 30% | 49% |
| Mastery | 89-100 | 0 | 5.5 | 4.6 | 100% | 95% | 49% | 14% | 14% | 36% |
| Shared Ends | 101-120 | 0 | 5.1 | 4.8 | 100% | 96% | 47% | 11% | 9% | 38% |
| Many Runs | 121-140 | 0 | 5.2 | 4.9 | 100% | 95% | 38% | 6% | 6% | 28% |
| Networks | 141-160 | 0 | 4.9 | 4.5 | 100% | 94% | 34% | 5% | 3% | 23% |
| Sections | 161-180 | 0 | 4.7 | 4.4 | 100% | 93% | 26% | 3% | 2% | 18% |
| The Limit | 181-200 | 0 | 4.5 | 4.4 | 100% | 92% | 20% | 2% | 1% | 14% |


## Which measurement predicts failure?

Correlation with success rate at `typical eye` over the 200 fair levels. Positive means more of the quantity is an easier level, so the channel measurements should come out positive and `unpinned runs` negative.

| quantity | Pearson r | Spearman rho |
|---|---|---|
| between-run separation | +0.402 | +0.841 |
| within-run step | +0.762 | +0.847 |
| unpinned runs (count) | -0.030 | -0.052 |
| hardest bank margin | +0.341 | +0.841 |
| bank size | -0.882 | -0.881 |


Bank size is in the table as a confound check: late levels have both tighter colours and more decisions, so a channel measurement only earns its keep if it beats plain counting. Success is a whole-board test, so it punishes size twice over (thirty decisions at 99% each still lose a quarter of the time). The table below removes that by asking the same question per cell.

| quantity | Pearson r vs per-cell error | Spearman rho |
|---|---|---|
| between-run separation | -0.391 | -0.775 |
| within-run step | -0.706 | -0.784 |
| unpinned runs (count) | +0.093 | +0.132 |
| hardest bank margin | -0.329 | -0.777 |
| bank size | +0.775 | +0.756 |


Negative is what a difficulty measurement should be here: more separation, fewer errors. Note that `within-run step` and `hardest bank margin` are the same number on 163 of the 200 fair levels, because the closest pair in the bank is almost always two neighbours on one run. The step is the more useful of the two to author against, since it is the quantity the generator can set directly.


Banded by between-run separation against the perceptual noise:

| band | levels | mean success | mean wrong cells |
|---|---|---|---|
| under 2 sigma (coin flip) | 2 | 38% | 2.44 |
| 2 to 3 sigma (strained) | 104 | 37% | 2.41 |
| 3 to 5 sigma (workable) | 59 | 70% | 0.98 |
| over 5 sigma (comfortable) | 35 | 94% | 0.16 |


Banded by within-run step against the perceptual noise:

| band | levels | mean success | mean wrong cells |
|---|---|---|---|
| under 2 sigma (coin flip) | 2 | 25% | 2.95 |
| 2 to 3 sigma (strained) | 132 | 41% | 2.22 |
| 3 to 5 sigma (workable) | 56 | 88% | 0.37 |
| over 5 sigma (comfortable) | 10 | 100% | 0.00 |


## Settings used

| condition | sigma | k | t | misclick | mean success (fair) | fair levels above 90% |
|---|---|---|---|---|---|---|
| noise-free control | 0 | 0 | 0 | 0 | 100% | 200 |
| sharp eye | 1 | 0 | 1.5 | 0 | 96% | 179 |
| typical eye | 2 | 0 | 1.5 | 0 | 57% | 46 |
| tired eye | 3 | 0 | 1.5 | 0 | 31% | 24 |
| compressed 50% | 1 | 0.5 | 1.5 | 0 | 34% | 33 |
| typical eye + fumbles | 2 | 0 | 1.5 | 0.02 | 46% | 23 |


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

