"""Durak rules engine — pure, seeded, and deterministic.

Durak is the one classic card game whose base loop is already combat: one
player attacks, the other must beat every card played or pick the whole lot
up. Nothing has to be bolted on to make it a roguelike fight. That is the
entire reason this prototype exists, so the engine's job is to be a faithful,
boring implementation of the rules, with the roguelike hooks kept somewhere a
rules bug cannot hide inside them (see relics.py).

Scope: two players, 36 cards (6 to Ace), one trump suit.

Deliberately asymmetric decks. In parlour Durak both players draw from one
shared talon, which would mean every card the player adds to their deck is a
card the enemy might draw. That is an interesting tension and a terrible
build: what you buy has to be legibly yours. So each side brings its own deck
and draws from its own talon, and the encounter declares the trump suit
instead of reading it off the bottom card. Suit distribution therefore becomes
a real build axis — a deck stacked in one suit is devastating under the right
banner and brittle under the wrong one.

Determinism. Every random draw goes through SeededRNG (splitmix64, the same
generator and constants as ChromaticOrder/Core/SeededRNG.swift) so a Swift
port reproduces these exact matches. Shuffling and policy noise are drawn
from SEPARATE streams on purpose: the playtest harness needs to hold the
decks fixed while it varies player skill, which it cannot do if one extra
coin flip inside a policy shifts every later shuffle.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------- randomness

_MASK = (1 << 64) - 1
_GOLDEN = 0x9E3779B97F4A7C15


class SeededRNG:
    """splitmix64. Mirrors SeededRNGRef in the Swift app, zero-remap included."""

    __slots__ = ("state",)

    def __init__(self, seed: int) -> None:
        self.state = _GOLDEN if seed == 0 else (seed & _MASK)

    def next(self) -> int:
        self.state = (self.state + _GOLDEN) & _MASK
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & _MASK
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & _MASK
        return (z ^ (z >> 31)) & _MASK

    def below(self, n: int) -> int:
        """Uniform in [0, n). Rejection-free; the modulo bias is ~2**-58 here."""
        return self.next() % n if n > 0 else 0

    def chance(self, p: float) -> bool:
        """True with probability p."""
        if p <= 0.0:
            return False
        if p >= 1.0:
            return True
        return (self.next() >> 11) / float(1 << 53) < p

    def shuffled(self, items: list) -> list:
        """Fisher-Yates on a copy, so the caller's list is left alone."""
        out = list(items)
        for i in range(len(out) - 1, 0, -1):
            j = self.below(i + 1)
            out[i], out[j] = out[j], out[i]
        return out


# --------------------------------------------------------------------- cards

SUITS = ("S", "H", "D", "C")
SUIT_PIPS = {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
RANKS = (6, 7, 8, 9, 10, 11, 12, 13, 14)
RANK_NAMES = {11: "J", 12: "Q", 13: "K", 14: "A"}


@dataclass(frozen=True, order=True)
class Card:
    rank: int
    suit: str

    def __str__(self) -> str:
        return f"{RANK_NAMES.get(self.rank, self.rank)}{SUIT_PIPS[self.suit]}"

    __repr__ = __str__


def full_deck() -> list[Card]:
    """The standard 36-card Durak deck, in a fixed order. Shuffle before use."""
    return [Card(r, s) for s in SUITS for r in RANKS]


def parse_card(text: str) -> Card:
    """'AS' / '10H' / 'JD' -> Card. Only used by tests and the CLI."""
    text = text.strip().upper()
    body, suit = text[:-1], text[-1]
    inverse = {v: k for k, v in RANK_NAMES.items()}
    rank = inverse.get(body, None)
    if rank is None:
        rank = int(body)
    if suit not in SUITS or rank not in RANKS:
        raise ValueError(f"not a Durak card: {text!r}")
    return Card(rank, suit)


def beats(defence: Card, attack: Card, trump: str) -> bool:
    """Can `defence` legally beat `attack`?

    Same suit and higher rank, or any trump against a non-trump. Trump is only
    ever beaten by a higher trump, which falls out of the first clause.
    """
    if defence.suit == attack.suit:
        return defence.rank > attack.rank
    return defence.suit == trump and attack.suit != trump


def card_power(card: Card, trump: str) -> int:
    """Sort key for 'how much does spending this hurt'. Trumps outrank all."""
    return card.rank + (100 if card.suit == trump else 0)


# --------------------------------------------------------------------- table

@dataclass
class Table:
    """The cards in play for one bout.

    `attacks[i]` is answered by `defences[i]`, which is None until it is beaten.
    """

    attacks: list[Card] = field(default_factory=list)
    defences: list[Optional[Card]] = field(default_factory=list)

    def __len__(self) -> int:
        return len(self.attacks)

    @property
    def unbeaten(self) -> list[int]:
        return [i for i, d in enumerate(self.defences) if d is None]

    @property
    def ranks_in_play(self) -> set[int]:
        """Ranks a follow-up attack card is allowed to match."""
        out = {c.rank for c in self.attacks}
        out.update(d.rank for d in self.defences if d is not None)
        return out

    def all_cards(self) -> list[Card]:
        out = list(self.attacks)
        out.extend(d for d in self.defences if d is not None)
        return out

    def add_attack(self, card: Card) -> None:
        self.attacks.append(card)
        self.defences.append(None)

    def add_defence(self, index: int, card: Card) -> None:
        self.defences[index] = card

    def clear(self) -> list[Card]:
        out = self.all_cards()
        self.attacks.clear()
        self.defences.clear()
        return out


# --------------------------------------------------------------------- sides

@dataclass
class Side:
    """One player's private state: hand, personal talon, and identity."""

    name: str
    hand: list[Card] = field(default_factory=list)
    talon: list[Card] = field(default_factory=list)
    discard: list[Card] = field(default_factory=list)

    @property
    def out_of_cards(self) -> bool:
        return not self.hand and not self.talon

    def draw_to(self, size: int) -> None:
        while len(self.hand) < size and self.talon:
            self.hand.append(self.talon.pop())

    def sorted_hand(self, trump: str) -> list[Card]:
        return sorted(self.hand, key=lambda c: card_power(c, trump))


# ------------------------------------------------------------------- outcome

BOUT_BEATEN = "beaten"   # defender survived; cards go to the discard
BOUT_TAKEN = "taken"     # defender picked the table up


@dataclass
class BoutRecord:
    """What happened in one bout. The harness reads these, not the log text."""

    attacker: str
    defender: str
    outcome: str
    attack_cards: int
    taken_cards: int
    # Cards that got through unanswered. The run layer bills wounds on this
    # rather than on the whole pickup: "what got past you" is a damage model
    # a player can read off the table, and it keeps partial defence worth
    # doing, which vanilla Durak does not.
    unbeaten_taken: int = 0
    deflected: bool = False


@dataclass
class MatchResult:
    winner: Optional[str]     # None on a draw
    bouts: int
    records: list[BoutRecord]
    cards_taken: dict[str, int]

    @property
    def drawn(self) -> bool:
        return self.winner is None


# --------------------------------------------------------------------- match

MAX_ATTACK_CARDS = 6
HAND_SIZE = 6
BOUT_LIMIT = 400  # safety net; a real match is far shorter


class Match:
    """One duel. Policies decide; this class only enforces and records.

    The engine calls into `relics` at every point the rules can be bent, so a
    relic never needs to reach into match state itself. `relics` may be None,
    which means vanilla Durak.
    """

    def __init__(
        self,
        player: Side,
        enemy: Side,
        trump: str,
        player_policy,
        enemy_policy,
        rng: SeededRNG,
        relics=None,
        first_attacker: str = "player",
    ) -> None:
        self.sides = {"player": player, "enemy": enemy}
        self.policies = {"player": player_policy, "enemy": enemy_policy}
        self.trump = trump
        self.rng = rng
        self.relics = relics
        self.table = Table()
        self.records: list[BoutRecord] = []
        self.cards_taken = {"player": 0, "enemy": 0}
        self.attacker = first_attacker

    # -- helpers ----------------------------------------------------------

    def _hand_size(self, who: str) -> int:
        base = HAND_SIZE
        if self.relics is not None:
            base = self.relics.hand_size(base, who)
        return base

    def _attack_cap(self, defender: str) -> int:
        cap = MAX_ATTACK_CARDS
        if self.relics is not None:
            cap = self.relics.attack_cap(cap, defender)
        # Never attack with more cards than the defender can possibly answer.
        return min(cap, len(self.sides[defender].hand) + len(self.table))

    def _can_beat(self, defence: Card, attack: Card, defender: str) -> bool:
        base = beats(defence, attack, self.trump)
        if self.relics is not None:
            return self.relics.can_beat(defence, attack, self.trump, base, defender)
        return base

    def legal_defences(self, defender: str, index: int) -> list[Card]:
        attack = self.table.attacks[index]
        hand = self.sides[defender].hand
        return [c for c in hand if self._can_beat(c, attack, defender)]

    def legal_additions(self, attacker: str, defender: str) -> list[Card]:
        """Cards the attacker may pile on mid-bout."""
        if len(self.table) >= self._attack_cap(defender):
            return []
        allowed = self.table.ranks_in_play
        return [c for c in self.sides[attacker].hand if c.rank in allowed]

    # -- the bout ---------------------------------------------------------

    def play_bout(self) -> BoutRecord:
        attacker = self.attacker
        defender = "enemy" if attacker == "player" else "player"
        atk_side, def_side = self.sides[attacker], self.sides[defender]
        atk_policy, def_policy = self.policies[attacker], self.policies[defender]

        lead = atk_policy.choose_lead(self, attacker)
        if lead is None:  # nothing to attack with; treat as a beaten bout
            return self._finish_bout(attacker, defender, BOUT_BEATEN, 0, 0, 0)

        atk_side.hand.remove(lead)
        self.table.add_attack(lead)

        deflected = False
        # Deflection (the perevodnoy variant) is a relic, not a base rule, and
        # is only offered before the defender has answered anything.
        if self.relics is not None and self.relics.allows_deflect(defender):
            passed = def_policy.choose_deflect(self, defender)
            if passed is not None and passed.rank == lead.rank:
                if len(atk_side.hand) >= len(self.table) + 1:
                    def_side.hand.remove(passed)
                    self.table.add_attack(passed)
                    attacker, defender = defender, attacker
                    atk_side, def_side = def_side, atk_side
                    atk_policy, def_policy = def_policy, atk_policy
                    deflected = True

        taken = False
        while True:
            pending = self.table.unbeaten
            if pending:
                index = pending[0]
                options = self.legal_defences(defender, index)
                choice = def_policy.choose_defence(self, defender, index, options) if options else None
                if choice is None:
                    taken = True
                    break
                def_side.hand.remove(choice)
                self.table.add_defence(index, choice)
                continue

            # Everything answered. Can the attacker keep the pressure up?
            options = self.legal_additions(attacker, defender)
            if not options:
                break
            extra = atk_policy.choose_addition(self, attacker, options)
            if extra is None:
                break
            atk_side.hand.remove(extra)
            self.table.add_attack(extra)

        attack_count = len(self.table)
        if taken:
            # The defender eats the table, beaten cards included — unless a
            # relic says otherwise, in which case the spared cards are burned.
            # Split by index, not by value: the two sides own separate decks,
            # so the same card can legitimately be on the table twice.
            pending = set(self.table.unbeaten)
            unbeaten = [self.table.attacks[i] for i in pending]
            beaten_attacks = [c for i, c in enumerate(self.table.attacks) if i not in pending]
            # The defender's own spent cards are tracked apart from the
            # attacker's, because a relic that burns "the cards you beat" must
            # not also burn the cards you beat them WITH — those are the best
            # cards in the hand, and losing them measured as a downgrade.
            own_defences = [d for d in self.table.defences if d is not None]
            spoils = unbeaten + beaten_attacks + own_defences
            burned = []
            if self.relics is not None:
                spoils, burned = self.relics.split_pickup(
                    unbeaten, beaten_attacks, own_defences, defender)
            self.table.clear()
            def_side.hand.extend(spoils)
            atk_side.discard.extend(burned)
            self.cards_taken[defender] += len(spoils)
            outcome, taken_cards = BOUT_TAKEN, len(spoils)
            got_through = len(unbeaten)
        else:
            atk_side.discard.extend(self.table.clear())
            outcome, taken_cards, got_through = BOUT_BEATEN, 0, 0

        return self._finish_bout(attacker, defender, outcome, attack_count,
                                 taken_cards, got_through, deflected)

    def _finish_bout(
        self,
        attacker: str,
        defender: str,
        outcome: str,
        attack_cards: int,
        taken_cards: int,
        got_through: int = 0,
        deflected: bool = False,
    ) -> BoutRecord:
        # Refill: attacker first, then defender. Matters when a talon runs dry.
        for who in (attacker, defender):
            self.sides[who].draw_to(self._hand_size(who))

        # A beaten defender earns the attack; a defender who took it loses the turn.
        self.attacker = defender if outcome == BOUT_BEATEN else attacker

        record = BoutRecord(attacker, defender, outcome, attack_cards, taken_cards,
                            got_through, deflected)
        self.records.append(record)
        if self.relics is not None:
            self.relics.after_bout(record, self.sides, self.trump)
        return record

    def play(self) -> MatchResult:
        for _ in range(BOUT_LIMIT):
            player_out = self.sides["player"].out_of_cards
            enemy_out = self.sides["enemy"].out_of_cards
            if player_out or enemy_out:
                if player_out and enemy_out:
                    winner = None
                else:
                    winner = "player" if player_out else "enemy"
                return MatchResult(winner, len(self.records), self.records, dict(self.cards_taken))
            self.play_bout()

        # Ran to the limit. Fewest cards held wins; equal is a draw.
        p, e = len(self.sides["player"].hand), len(self.sides["enemy"].hand)
        winner = None if p == e else ("player" if p < e else "enemy")
        return MatchResult(winner, len(self.records), self.records, dict(self.cards_taken))


def deal(deck: list[Card], rng: SeededRNG, hand_size: int = HAND_SIZE) -> Side:
    """Shuffle a deck into a Side with a full opening hand."""
    side = Side(name="", talon=rng.shuffled(deck))
    side.draw_to(hand_size)
    return side
