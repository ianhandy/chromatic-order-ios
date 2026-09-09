"""Relics — the roguelike layer, expressed as bends in Durak's own rules.

The reason Durak is worth building on is that its rulebook is already full of
small levers, so relics do not have to invent vocabulary the way a poker
roguelike has to invent "mult". Every relic here is a sentence a Durak player
would already understand: refill to seven, pass the attack along, aces beat
anything, they can only come at you four at a time.

Only the player carries relics. The enemy plays vanilla Durak, which keeps the
simulator's question honest: how much does a given relic set move the win rate
against a fixed opponent?

Two rules for anything added here:

  * No hidden per-match state inside `can_beat`. The engine calls it to build
    the list of legal defences, not only when a card is actually played, so a
    "once per match" effect expressed this way would quietly show the policy
    a legal set it cannot really use. Charge-based effects belong in a hook
    the policy can see and spend deliberately.
  * A relic is a rule, not a number. "Trumps you pick up are free" reshapes
    which cards you want to eat. "+3 to everything" reshapes nothing.
"""

from __future__ import annotations

from dataclasses import dataclass

from engine import BOUT_BEATEN, BOUT_TAKEN, Card, card_power


@dataclass(frozen=True)
class Relic:
    key: str
    name: str
    text: str


CATALOGUE: dict[str, Relic] = {
    r.key: r
    for r in [
        Relic("deflection", "Deflection",
              "Pass an attack back by playing a card of the same rank."),
        Relic("ironbound", "Ironbound",
              "Trump cards you pick up cost you nothing."),
        Relic("duelist", "Duelist",
              "They may attack you with at most four cards in a bout."),
        Relic("hoard", "Hoard",
              "You refill to seven cards instead of six."),
        Relic("whetstone", "Whetstone",
              "Your sixes beat any card of their own suit."),
        Relic("ace_in_the_hole", "Ace in the Hole",
              "Your aces beat anything."),
        Relic("field_surgeon", "Field Surgeon",
              "Survive a bout of three or more cards and mend one wound."),
        Relic("reversal", "Reversal",
              "When you pick up, the cards you already beat are burned instead."),
        Relic("banner", "Banner",
              "You name the trump suit at the start of every encounter."),
        Relic("quartermaster", "Quartermaster",
              "Whenever you pick up, burn your worst card."),
    ]
}


class RelicSet:
    """The player's relics, composed into the hook surface the engine calls.

    Deliberately explicit: every hook reads the membership set and applies the
    relics that matter. No dispatch table, no plugin registry. A prototype's
    relic list is short and the Swift port of an if-statement is an
    if-statement.
    """

    def __init__(self, keys: list[str] | None = None, side: str = "player") -> None:
        keys = list(keys or [])
        unknown = [k for k in keys if k not in CATALOGUE]
        if unknown:
            raise ValueError(f"unknown relics: {unknown}")
        self.keys = set(keys)
        self.side = side
        self.pending_heal = 0  # drained by the run loop after each bout

    def __contains__(self, key: str) -> bool:
        return key in self.keys

    def has(self, key: str) -> bool:
        return key in self.keys

    def names(self) -> list[str]:
        return [CATALOGUE[k].name for k in sorted(self.keys)]

    # -- engine hooks -----------------------------------------------------

    def hand_size(self, base: int, who: str) -> int:
        if who == self.side and "hoard" in self.keys:
            return base + 1
        return base

    def attack_cap(self, base: int, defender: str) -> int:
        if defender == self.side and "duelist" in self.keys:
            return min(base, 4)
        return base

    def can_beat(self, defence: Card, attack: Card, trump: str, base: bool, defender: str) -> bool:
        if base or defender != self.side:
            return base
        if "ace_in_the_hole" in self.keys and defence.rank == 14:
            return True
        if "whetstone" in self.keys and defence.rank == 6 and defence.suit == attack.suit:
            return True
        return False

    def allows_deflect(self, defender: str) -> bool:
        return defender == self.side and "deflection" in self.keys

    def split_pickup(self, unbeaten: list[Card], beaten_attacks: list[Card],
                     own_defences: list[Card], defender: str):
        """Return (cards taken into hand, cards burned to the discard).

        Reversal burns the attacker's spent cards only. An earlier version
        burned the defender's spent cards along with them and measured -0.53
        encounters: in vanilla Durak a failed defence at least hands your
        cards back, so throwing away the high cards you just spent beating
        things is a downgrade wearing a relic's clothes.
        """
        if defender == self.side and "reversal" in self.keys:
            return list(unbeaten) + list(own_defences), list(beaten_attacks)
        return unbeaten + beaten_attacks + own_defences, []

    def after_bout(self, record, sides: dict, trump: str) -> None:
        """Effects that fire once a bout has fully resolved.

        Quartermaster lives here rather than on the refill, and only on a
        pickup, because of the sharpest lesson this prototype taught: card
        count is the dominant currency in Durak, so any effect that changes it
        every single bout runs away. Burning a card per refill measured +2.85
        depth and a 78% clear rate. Tied to pickups it offsets the damage you
        just took and nothing more.
        """
        me = self.side
        if "field_surgeon" in self.keys:
            if (record.defender == me and record.outcome == BOUT_BEATEN
                    and record.attack_cards >= 3):
                self.pending_heal += 1

        if "quartermaster" in self.keys:
            if record.defender == me and record.outcome == BOUT_TAKEN:
                hand = sides[me].hand
                if hand:
                    worst = min(hand, key=lambda c: card_power(c, trump))
                    hand.remove(worst)
                    sides[me].discard.append(worst)

    # -- run hooks --------------------------------------------------------

    def chooses_trump(self) -> bool:
        return "banner" in self.keys

    def pickup_hp_cost(self, cards: list[Card], trump: str) -> int:
        """Wounds taken for eating a table. One per card, trumps maybe free."""
        if "ironbound" in self.keys:
            return sum(1 for c in cards if c.suit != trump)
        return len(cards)

    def take_heal(self) -> int:
        out, self.pending_heal = self.pending_heal, 0
        return out


VANILLA = RelicSet([])
