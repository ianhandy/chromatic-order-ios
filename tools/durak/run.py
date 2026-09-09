"""The run: a gauntlet of duels, a deck you reshape, and wounds you carry.

Structure

  A run is a sequence of encounters. Each encounter is one duel of Durak
  against an opponent with its own deck, its own skill, and a declared trump
  suit. Win and you move on; lose and the run is over.

Wounds

  Losing a duel ends a run outright, but that alone would make every encounter
  a coin flip with no memory. Wounds are the memory. Picking a table up — the
  move Durak already punishes — costs health that carries across encounters,
  so *how* you win matters as much as whether you did. At zero you are done,
  even mid-duel, even while winning.

  That single rule creates the tension the whole design rests on: spend a
  trump to survive the bout, or eat the cards and pay for it later. The policy
  is told its health fraction so it can actually feel that trade, and the
  first two cards of any pickup are free so that ordinary Durak attrition does
  not simply drain a bar.

Trump as a difficulty lever

  From the fourth encounter on, the opponent names the trump suit, and it
  picks the suit the player's deck is thinnest in. A deck stacked in one suit
  is therefore a real gamble rather than a free win, and the Banner relic —
  which takes that choice back — has an obvious job.

Archetypes

  A simulated run needs a shopping policy, and the interesting question is
  which *build* is broken, not which click is. The archetypes below stand in
  for the ways people actually play a deck-builder: hoard relics, thin the
  deck, chase one suit, chase high cards.
"""

from __future__ import annotations

import zlib
from dataclasses import dataclass, field
from typing import Optional

from engine import (
    RANKS, SUITS, Card, Match, SeededRNG, Side, full_deck,
)
from policy import SKILLS, make_policy
from relics import CATALOGUE, RelicSet

# ------------------------------------------------------------------- config


@dataclass
class RunConfig:
    encounters: int = 8
    # `tune.py health` shows the curve goes FLAT above 10 — mean depth 4.29,
    # 4.29, 4.38, 4.45 at 10/12/16/20 — and Ironbound, which exists purely to
    # blunt wounds, drops from +0.11 to -0.14 across that range. A resource
    # nobody runs out of is not a resource, and every relic attached to it is
    # dead on arrival. At 8 it binds: Ironbound is worth +0.35, and wipes run
    # at 15% against 11% at the flat end.
    starting_health: int = 8
    # Both sides field a talon of exactly this many cards, drawn from their
    # deck. Without it, deck SIZE decides the duel outright: Durak is won by
    # shedding your last card, so the player with more cards simply loses, and
    # "remove a card" becomes the only move in the shop. Fixing the talon makes
    # the deck a pool you draw quality from, so thinning buys consistency and
    # adding buys ceiling — the trade every deck-builder actually runs on.
    talon_size: int = 24
    free_cards_per_pickup: int = 0   # wounds are already only what got through
    starter_ranks: tuple[int, ...] = (6, 7, 8, 9, 10, 11, 12, 13)  # no aces
    shop_offers: int = 3
    # Two picks, not one. At one pick the player barely scales: per-encounter
    # win rates sat near 80% flat and eight of those compound to 17%, which
    # reads as attrition rather than a run going well or badly. Progression has
    # to outrun the difficulty curve for the curve to feel like one.
    shop_picks: int = 2


def starter_deck(config: RunConfig) -> list[Card]:
    return [Card(r, s) for s in SUITS for r in config.starter_ranks]


# ---------------------------------------------------------------- opponents

@dataclass
class Opponent:
    name: str
    skill: str
    deck: list[Card]
    picks_trump: bool


OPPONENT_NAMES = [
    "The Ferryman", "Grandmother", "The Tax Collector", "Two Coats",
    "The Winter Soldier", "The Cardsharp", "The Magistrate", "The Fool Himself",
]


def opponent_for(depth: int, rng: SeededRNG) -> Opponent:
    """Difficulty comes from three dials: skill, deck quality, trump choice."""
    # Tuned with `tune.py difficulty` against a target of roughly half of
    # sharp runs and a quarter of typical runs clearing all eight. The dial
    # that matters is the opponent's rank floor, not its skill: a deck with no
    # sixes in it simply has no cards you can cheaply beat.
    if depth <= 2:
        skill, ranks = "tired", (6, 7, 8, 9, 10, 11, 12)
    elif depth <= 4:
        skill, ranks = "typical", (6, 7, 8, 9, 10, 11, 12, 13)
    elif depth <= 6:
        skill, ranks = "typical", (6, 7, 8, 9, 10, 11, 12, 13, 14)
    elif depth <= 7:
        skill, ranks = "typical", (7, 8, 9, 10, 11, 12, 13, 14)
    else:
        # The last opponent is the only one who plays well. Late difficulty is
        # otherwise carried by card quality: making the endgame opponents sharp
        # AS WELL cost a typical player nine points of clear rate for no change
        # in how the run reads.
        skill, ranks = "sharp", (7, 8, 9, 10, 11, 12, 13, 14)

    deck = [Card(r, s) for s in SUITS for r in ranks]
    if depth >= 7:  # a second helping of the good stuff
        deck.extend(Card(14, s) for s in SUITS)
    name = OPPONENT_NAMES[min(depth - 1, len(OPPONENT_NAMES) - 1)]
    return Opponent(name, skill, deck, picks_trump=depth >= 4)


def weakest_suit(deck: list[Card]) -> str:
    """The suit this deck would least like to see named trump."""
    def strength(suit: str) -> tuple[int, int]:
        cards = [c for c in deck if c.suit == suit]
        return (sum(c.rank for c in cards), len(cards))
    return min(SUITS, key=strength)


def strongest_suit(deck: list[Card]) -> str:
    def strength(suit: str) -> tuple[int, int]:
        cards = [c for c in deck if c.suit == suit]
        return (sum(c.rank for c in cards), len(cards))
    return max(SUITS, key=strength)


# ---------------------------------------------------------------- the shop

ADD_RANKS = (14, 13, 12)
OFFER_RELIC, OFFER_ADD, OFFER_REMOVE, OFFER_HEAL = "relic", "add", "remove", "heal"


@dataclass
class Offer:
    kind: str
    relic: Optional[str] = None
    card: Optional[Card] = None
    amount: int = 0

    def label(self) -> str:
        if self.kind == OFFER_RELIC:
            return CATALOGUE[self.relic].name
        if self.kind == OFFER_ADD:
            return f"add {self.card}"
        if self.kind == OFFER_REMOVE:
            return f"remove {self.card}"
        return f"mend {self.amount}"


def roll_offers(state: "RunState", rng: SeededRNG, count: int) -> list[Offer]:
    """A pool wide enough that an archetype can actually pursue a plan.

    A three-card shop drawn from a four-offer pool is not a choice, it is a
    formality: every build ends up holding the same cards. Offering two of
    each kind lets the thinner thin and the trump stacker stack.
    """
    pool: list[Offer] = []
    unowned = [k for k in sorted(CATALOGUE) if k not in state.relics.keys]
    for _ in range(2):
        if unowned:
            pool.append(Offer(OFFER_RELIC, relic=unowned[rng.below(len(unowned))]))
    for _ in range(2):
        pool.append(Offer(OFFER_ADD, card=Card(ADD_RANKS[rng.below(len(ADD_RANKS))],
                                               SUITS[rng.below(len(SUITS))])))
    low = [c for c in state.deck if c.rank <= 8]
    for _ in range(2):
        if low:
            pool.append(Offer(OFFER_REMOVE, card=low[rng.below(len(low))]))
    pool.append(Offer(OFFER_HEAL, amount=4))
    return rng.shuffled(pool)[:max(count, 4)]


class Archetype:
    """A shopping policy. Ranks offers; the run takes its favourite."""

    def __init__(self, key: str) -> None:
        self.key = key

    def rank(self, offer: Offer, state: "RunState") -> float:
        health_pressure = 1.0 - (state.health / max(1, state.config.starting_health))
        if offer.kind == OFFER_HEAL:
            return 2.0 + 6.0 * health_pressure

        if self.key == "relic_hunter":
            return {OFFER_RELIC: 10.0, OFFER_ADD: 3.0, OFFER_REMOVE: 2.0}.get(offer.kind, 0.0)

        if self.key == "thinner":
            return {OFFER_REMOVE: 10.0, OFFER_RELIC: 5.0, OFFER_ADD: 1.0}.get(offer.kind, 0.0)

        if self.key == "high_roller":
            if offer.kind == OFFER_ADD:
                return 6.0 + offer.card.rank / 10.0
            return {OFFER_RELIC: 5.0, OFFER_REMOVE: 4.0}.get(offer.kind, 0.0)

        if self.key == "trump_stack":
            if offer.kind == OFFER_ADD:
                return 9.0 if offer.card.suit == strongest_suit(state.deck) else 2.0
            return {OFFER_RELIC: 5.0, OFFER_REMOVE: 4.0}.get(offer.kind, 0.0)

        # balanced
        return {OFFER_RELIC: 6.0, OFFER_REMOVE: 5.0, OFFER_ADD: 5.0}.get(offer.kind, 0.0)


ARCHETYPES = ("balanced", "relic_hunter", "thinner", "high_roller", "trump_stack")


# ----------------------------------------------------------------- the run

@dataclass
class EncounterResult:
    depth: int
    opponent: str
    trump: str
    won: bool
    bouts: int
    cards_taken: int
    wounds: int
    health_after: int


@dataclass
class RunState:
    config: RunConfig
    deck: list[Card]
    relics: RelicSet
    health: int
    archetype: Archetype
    log: list[EncounterResult] = field(default_factory=list)

    @property
    def depth_reached(self) -> int:
        return sum(1 for r in self.log if r.won)


def _trump_for(state: RunState, opponent: Opponent, rng: SeededRNG) -> str:
    if state.relics.chooses_trump():
        return strongest_suit(state.deck)
    if opponent.picks_trump:
        return weakest_suit(state.deck)
    return SUITS[rng.below(len(SUITS))]


def play_encounter(state: RunState, depth: int, seeds: dict[str, int], skill_key: str) -> EncounterResult:
    """One duel. `seeds` splits shuffling from policy noise deliberately.

    Holding the deck seed fixed while varying the policy seed is what lets the
    harness compare skill conditions on identical decks, the same way the
    campaign playtest shares its random draws across conditions.
    """
    deck_rng = SeededRNG(seeds["deck"])
    policy_rng = SeededRNG(seeds["policy"])
    enemy_rng = SeededRNG(seeds["enemy"])
    match_rng = SeededRNG(seeds["match"])

    opponent = opponent_for(depth, SeededRNG(seeds["deck"] ^ 0xABCDEF))
    trump = _trump_for(state, opponent, deck_rng)

    size = state.config.talon_size
    hand = state.relics.hand_size(6, "player")
    player = Side(name="player", talon=deck_rng.shuffled(state.deck)[:size])
    player.draw_to(hand)
    enemy = Side(name="enemy", talon=deck_rng.shuffled(opponent.deck)[:size])
    enemy.draw_to(6)

    player_policy = make_policy(skill_key, policy_rng)
    player_policy.hp_fraction = state.health / max(1, state.config.starting_health)
    enemy_policy = make_policy(opponent.skill, enemy_rng)

    match = Match(player, enemy, trump, player_policy, enemy_policy, match_rng,
                  relics=state.relics, first_attacker="player")

    # Wounds have to accrue per bout, not at the end: a run can end mid-duel.
    health = state.health
    wounds = 0
    free = state.config.free_cards_per_pickup
    for _ in range(400):
        if player.out_of_cards or enemy.out_of_cards or health <= 0:
            break
        record = match.play_bout()
        if record.outcome == "taken" and record.defender == "player":
            # spoils are appended unbeaten-first, so the head of the slice is
            # exactly the cards that got past the defence.
            taken = player.hand[-record.taken_cards:] if record.taken_cards else []
            billable = taken[:record.unbeaten_taken]
            cost = state.relics.pickup_hp_cost(billable, trump)
            cost = max(0, cost - free)
            wounds += cost
            health -= cost
        healed = state.relics.take_heal()
        if healed:
            health = min(state.config.starting_health, health + healed)
            wounds -= healed

    if health <= 0:
        won = False
    elif player.out_of_cards and not enemy.out_of_cards:
        won = True
    elif enemy.out_of_cards and not player.out_of_cards:
        won = False
    else:
        won = len(player.hand) < len(enemy.hand)

    result = EncounterResult(
        depth=depth,
        opponent=opponent.name,
        trump=trump,
        won=won,
        bouts=len(match.records),
        cards_taken=match.cards_taken["player"],
        wounds=wounds,
        health_after=max(0, health),
    )
    state.health = max(0, health)
    state.log.append(result)
    return result


def apply_offer(state: RunState, offer: Offer) -> None:
    if offer.kind == OFFER_RELIC:
        state.relics.keys.add(offer.relic)
    elif offer.kind == OFFER_ADD:
        state.deck.append(offer.card)
    elif offer.kind == OFFER_REMOVE:
        if offer.card in state.deck:
            state.deck.remove(offer.card)
    elif offer.kind == OFFER_HEAL:
        state.health = min(state.config.starting_health, state.health + offer.amount)


def play_run(
    seed: int,
    skill_key: str = "typical",
    archetype_key: str = "balanced",
    config: Optional[RunConfig] = None,
    starting_relics: Optional[list[str]] = None,
) -> RunState:
    """One full gauntlet. Deterministic in `seed` for a given skill/archetype."""
    config = config or RunConfig()
    state = RunState(
        config=config,
        deck=starter_deck(config),
        relics=RelicSet(starting_relics or []),
        health=config.starting_health,
        archetype=Archetype(archetype_key),
    )

    shop_rng = SeededRNG(seed ^ 0x5EED)
    for depth in range(1, config.encounters + 1):
        seeds = {
            # Deck and opponent draws depend on the run seed and depth only, so
            # they stay put while skill and archetype vary.
            "deck": seed * 1000 + depth,
            "enemy": seed * 1000 + depth + 500_000,
            "match": seed * 1000 + depth + 900_000,
            # Policy noise gets its own stream, keyed by skill. crc32, not
            # hash(): Python randomises string hashing per process, so hash()
            # here made every sweep silently irreproducible between runs.
            "policy": seed * 1000 + depth + 100_000 + (zlib.crc32(skill_key.encode()) & 0xFFFF),
        }
        result = play_encounter(state, depth, seeds, skill_key)
        if not result.won or state.health <= 0:
            break
        offers = roll_offers(state, shop_rng, config.shop_offers)
        for _ in range(config.shop_picks):
            if not offers:
                break
            best = max(offers, key=lambda o: state.archetype.rank(o, state))
            offers.remove(best)
            apply_offer(state, best)

    return state
