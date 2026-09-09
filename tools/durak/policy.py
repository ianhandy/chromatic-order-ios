"""Player policies, modelled at several levels of skill.

The campaign playtest in tools/campaign does not ask "is this level solvable";
it asks "how often does a person land it, given that a person sees colour
through noise and fumbles the occasional drag". The same distinction applies
here. A perfect-information search would tell us Durak is solvable. It would
tell us nothing about whether a relic is broken in the hands of someone
playing on a bus.

So skill is modelled explicitly, along the axes Durak players actually differ
on:

  * trump discipline — how readily you burn a trump to save a small table.
    This is the single biggest skill gap in Durak. Weak players spend the ace
    of trumps to avoid picking up two low cards, then have nothing left.
  * blunder rate — how often you simply play something else that was legal.
  * deflection sight — how often you notice you could pass the attack along.

The conditions below are named to match the campaign report so the two
harnesses read alike: sharp, typical, tired, plus reckless as a control that
never surrenders a bout.

Policies never mutate match state. They pick; the engine enforces.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from engine import Card, SeededRNG, card_power


@dataclass
class Skill:
    key: str
    label: str
    # How reluctant the player is to spend a trump as an ATTACK card. Named
    # for the instinct, not for the virtue: `tune.py discipline` shows the
    # payoff is monotonically DECREASING in it, so hoarding trumps on offence
    # is simply the beginner's mistake. Durak is won by shedding.
    trump_discipline: float
    blunder: float            # chance of taking a random legal option instead
    deflect_sight: float      # chance of spotting an available deflection
    # How many trump points one wound is worth. This is THE skill axis: a
    # defender is forever choosing between spending a high trump and letting a
    # card through. Too low and you eat everything; too high and you burn the
    # ace of trumps to stop a six. The tuned value lives in SKILLS below and
    # was found by sweep, not by taste — see tune.py.
    exchange: float


SKILLS: dict[str, Skill] = {
    s.key: s
    for s in [
        # exchange values come from `python3 tune.py exchange`. 8 is the peak:
        # it works out to "only let a card through if stopping it would cost
        # the ace of trumps", which is both optimal here and a rule a person
        # can actually hold in their head. Lower values eat the player alive.
        Skill("sharp", "sharp", trump_discipline=0.10, blunder=0.00, deflect_sight=1.00, exchange=8.0),
        Skill("typical", "typical", trump_discipline=0.35, blunder=0.08, deflect_sight=0.70, exchange=5.0),
        Skill("tired", "tired", trump_discipline=0.65, blunder=0.22, deflect_sight=0.35, exchange=2.0),
        # Control, not a skill level: never gives up a bout, however costly.
        Skill("reckless", "reckless", trump_discipline=0.10, blunder=0.10, deflect_sight=0.50, exchange=99.0),
    ]
}


class GreedyPolicy:
    """Cheapest-card Durak with a trump budget and a surrender rule.

    `hp_fraction` is set by the run loop before each encounter. A player on
    their last legs defends harder, because picking up is what kills them —
    the policy has to know that or the harness measures a player who cheerfully
    bleeds out while holding the ace of trumps.
    """

    def __init__(self, skill: Skill, rng: SeededRNG) -> None:
        self.skill = skill
        self.rng = rng
        self.hp_fraction = 1.0

    # -- helpers ----------------------------------------------------------

    def _maybe_blunder(self, options: list[Card]) -> Optional[Card]:
        if len(options) > 1 and self.rng.chance(self.skill.blunder):
            return options[self.rng.below(len(options))]
        return None

    def _cheapest(self, options: list[Card], trump: str) -> Card:
        return min(options, key=lambda c: card_power(c, trump))

    # -- attacking --------------------------------------------------------

    def choose_lead(self, match, who: str) -> Optional[Card]:
        hand = match.sides[who].hand
        if not hand:
            return None
        slip = self._maybe_blunder(hand)
        if slip is not None:
            return slip
        return self._cheapest(hand, match.trump)

    def choose_addition(self, match, who: str, options: list[Card]) -> Optional[Card]:
        """Pile on. Durak is won by shedding, so the default is always to add.

        The one restraint is trumps. Early, with a talon still to draw from,
        a good trump thrown onto a bout the defender is already handling is
        just a donation. Late, with nothing left to draw, shedding beats
        hoarding and everything goes in.
        """
        trump = match.trump
        plain = [c for c in options if c.suit != trump]
        if plain:
            slip = self._maybe_blunder(plain)
            return slip if slip is not None else self._cheapest(plain, trump)

        endgame = not match.sides[who].talon
        if endgame:
            return self._cheapest(options, trump)
        # Discipline sets how high a trump you are willing to spend: a
        # disciplined player parts with a six, never with the king.
        cutoff = 6 + 8 * (1.0 - self.skill.trump_discipline)
        cheap = [c for c in options if c.rank <= cutoff]
        if not cheap:
            return None
        return self._cheapest(cheap, trump)

    # -- defending --------------------------------------------------------

    def choose_defence(self, match, who: str, index: int, options: list[Card]) -> Optional[Card]:
        trump = match.trump
        best = self._cheapest(options, trump)

        if self._should_surrender(match, who, best):
            return None

        slip = self._maybe_blunder(options)
        if slip is not None:
            return slip
        return best

    def _should_surrender(self, match, who: str, best: Card) -> bool:
        """Let this card through, or spend the trump it would take to stop it?

        Billing wounds on unanswered cards only (see run.py) turns this into a
        clean exchange: taking costs one wound per card still unbeaten, and
        defending costs whatever the cheapest legal card is worth. A plain card
        is free, so it is always spent. A trump has a price, and `exchange` is
        how many of those points the player thinks a wound is worth.
        """
        if best.suit != match.trump:
            return False  # a plain card is always worth spending
        if not match.sides[who].talon:
            return False  # endgame: the race to shed outweighs any reserve

        wounds = len(match.table.unbeaten)
        trump_cost = best.rank - 5  # six of trumps 1, ace of trumps 9
        # Near death, a wound is worth far more than any card in hand.
        aversion = 1.0 + 2.0 * (1.0 - self.hp_fraction)
        return trump_cost > wounds * self.skill.exchange * aversion

    def choose_deflect(self, match, who: str) -> Optional[Card]:
        """Pass the attack on by matching its rank, if we see it."""
        if not match.table.attacks:
            return None
        rank = match.table.attacks[0].rank
        matches = [c for c in match.sides[who].hand if c.rank == rank]
        if not matches:
            return None
        if not self.rng.chance(self.skill.deflect_sight):
            return None
        trump = match.trump
        plain = [c for c in matches if c.suit != trump]
        return self._cheapest(plain or matches, trump)


def make_policy(skill_key: str, rng: SeededRNG) -> GreedyPolicy:
    if skill_key not in SKILLS:
        raise ValueError(f"unknown skill {skill_key!r}; have {sorted(SKILLS)}")
    return GreedyPolicy(SKILLS[skill_key], rng)
