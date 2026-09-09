# Durak, as a roguelike

A playable, seeded prototype of the design, plus the Monte Carlo harness that
tunes it. Pure Python, no dependencies, nothing here ships in the app.

This is the balance layer, deliberately built before any Swift. The campaign in
`tools/campaign` was tuned the same way: simulate an imperfect player tens of
thousands of times, find the levels that fail, and only then commit to the
content. Every magic number in these files traces to a sweep in `tune.py`.

```
python3 -m unittest discover -s tools/durak -t tools/durak   # rules + balance audits
python3 tune.py difficulty     # does the gauntlet separate skill levels?
python3 tune.py relics         # is any relic broken?
python3 tune.py report         # regenerate playtest-report.md
```

## Why Durak

Every other card game needs a combat metaphor bolted on. Durak already is one.
One player attacks, the other beats every card or picks the whole lot up. The
cards are the resource, the trump suit is the economy, and the losing condition
is being the last player still holding anything.

That means relics can be written in the game's own vocabulary rather than in
invented currency. "They may attack you with at most four cards." "Trumps you
pick up cost you nothing." "Pass the attack back by matching its rank." Nobody
needs a tutorial for those, and none of them are a number going up.

## The design

**A run** is eight duels. Win and you move on, lose and it is over. Between
duels you take two picks from a shop: a relic, a card added, a card removed, or
some health back.

**Separate decks.** In parlour Durak both players draw from one talon, which
would mean every card you buy is a card the enemy might draw. Here each side
brings its own deck, and the encounter declares the trump suit.

**A fixed talon.** Both sides field exactly 24 cards drawn from their deck.
This is load-bearing, not a detail — see the first finding below.

**Wounds.** Cards that get past your defence cost health, and health carries
across encounters. At zero the run ends, even mid-duel, even while winning. So
the live decision in every bout is whether to spend a high trump or let the
card through, and that decision is priced.

**Trump as difficulty.** From the fourth encounter the opponent names trump,
and it names the suit your deck is thinnest in. Stacking one suit is a gamble,
and the Banner relic takes the choice back.

## What the simulation found

Six things, all of which would have been expensive to discover in Swift.

**Deck size alone decided the duel.** Durak is won by shedding your last card,
so under separate talons the player with more cards simply loses. Every run
died at the first encounter, and "remove a card" would have been the only real
move in the shop. Fixing the talon at 24 turns the deck into a pool you draw
quality from, so thinning buys consistency and adding buys ceiling.

**Card count is the dominant currency, and it broke three things.** A relic
letting follow-up attacks ignore the matching-rank rule cleared 97% of runs,
because that rule is the only brake on shedding. Narrowed to adjacent ranks it
still cleared 89%. Replaced with a card-burning effect that fired every refill,
it hit 78%. The rule that came out of it: a relic may change which cards you
can play, never how many. The surviving version, Quartermaster, fires only when
you pick up, and measures +0.75 encounters.

**Hoarding trumps on offence is simply wrong.** The sweep is monotone: mean
depth falls from 5.50 to 3.84 as the policy grows more reluctant to spend a
trump as an attack card. So "save your trumps" is modelled as the beginner's
mistake rather than the expert's discipline, which is also how it plays.

**The surrender decision is real, but narrow.** Sweeping what a wound is worth
in trump points peaks at 8 (48% clears), and 8 works out to a rule a person can
hold in their head: only let a card through if stopping it would cost the ace of
trumps. Never surrendering at all is measurably worse at 44%, so the decision
earns its place.

**Health above 10 was decorative.** Mean depth goes flat from 10 upward — 4.29
at 10, 4.31 at 12, 4.33 at 16, 4.36 at 20 — and Ironbound, which exists only to
blunt wounds, falls from +0.20 to -0.09 across that range. A resource nobody exhausts kills every relic
attached to it. Starting health is 8, where wounds bind and Ironbound is worth
+0.34.

**One relic was a downgrade in disguise.** Reversal burns the cards you already
beat instead of making you take them, and it measured -0.53 encounters, because
it also burned the cards you beat them *with* — the best cards in your hand. In
vanilla Durak a failed defence at least hands those back. Splitting the
attacker's spent cards from the defender's turned it into +0.54.

There was also a plain bug worth recording: policy noise was seeded from
Python's `hash()`, which is randomised per process, so no sweep reproduced
between runs until it moved to crc32.

## Where it stands

A sharp player clears 48% of runs, a typical player 24%, a tired one 0%. Every
relic is worth between +0.12 and +1.39 encounters, with nothing dead and nothing
dominant. Full tables in `playtest-report.md`.

## Open issues

**The hardest fight is the third, not the last.** A typical player wins 72% at
depth 3 and 82% at depth 8. Some of that is survivorship — weak builds are gone
by then — but the third encounter is where skill jumps and kings arrive at once,
and the wall is real.

**Specialising is punished.** The balanced shopper beats every specialist
archetype (3.82 against 3.19 to 3.46). A deck-builder where generic play wins
has no builds in it. The shop pool likely needs cards that reward commitment.

**Ace in the Hole is nearly dead** at +0.12, because the starter deck has no
aces and a run buys at most two. A conditional relic needs its enabler in the
shop.

**No economy.** Shop picks are free, which removes the whole gold-versus-power
axis. Deliberate: one variable at a time.

**The opponent plays vanilla Durak** with no relics of its own, which keeps the
relic measurements clean but means boss design is untested.

## Porting to Swift

`engine.py`, `relics.py` and `policy.py` are pure and side-effect free, and map
to structs directly. `SeededRNG` is splitmix64 with the same constants and the
same zero-seed remap as `ChromaticOrder/Core/SeededRNG.swift`, so a Swift port
reproduces these exact matches from the same seed — which makes the Python
report a usable oracle for the port, and daily seeded runs possible for free.

`run.py` and `tune.py` are the harness and stay in Python.
