"""Rules, determinism, and balance audits.

The first two classes are ordinary correctness tests. The third is the one
worth having, and it is modelled on ChromaticOrderTests/CampaignFairnessTests:
a test that fails when the *design* goes wrong rather than when the code does.

That file's argument is that a solver proving a board has one solution says
nothing about whether a person could find it, so the campaign gates on
playability instead. The same applies here. A Durak engine that obeys the
rules can still host a relic that clears 97% of runs, or a health bar nobody
ever empties. Those are the failures that reach players, and only a simulation
catches them, so they are asserted here alongside the rules.

Run:  python3 -m unittest discover -s tools/durak -t tools/durak
"""

from __future__ import annotations

import statistics
import unittest

from engine import (
    BOUT_BEATEN, BOUT_TAKEN, Card, Match, SeededRNG, Side, Table,
    beats, full_deck, parse_card,
)
from policy import SKILLS, make_policy
from relics import CATALOGUE, RelicSet
from run import RunConfig, play_run


def _duel(seed: int, a="typical", b="typical", relics=None, first="player"):
    rng = SeededRNG(seed)
    deck = full_deck()
    player = Side("player", talon=rng.shuffled(deck)[:24])
    player.draw_to(6)
    enemy = Side("enemy", talon=rng.shuffled(deck)[:24])
    enemy.draw_to(6)
    match = Match(player, enemy, "H",
                  make_policy(a, SeededRNG(seed ^ 0x11)),
                  make_policy(b, SeededRNG(seed ^ 0x22)),
                  SeededRNG(seed ^ 0x33), relics, first_attacker=first)
    return match, match.play()


class TestRules(unittest.TestCase):
    def test_same_suit_higher_rank_beats(self):
        self.assertTrue(beats(parse_card("9S"), parse_card("7S"), "H"))
        self.assertFalse(beats(parse_card("7S"), parse_card("9S"), "H"))

    def test_equal_rank_does_not_beat(self):
        self.assertFalse(beats(parse_card("9S"), parse_card("9S"), "H"))

    def test_trump_beats_any_plain_card(self):
        self.assertTrue(beats(parse_card("6H"), parse_card("AS"), "H"))

    def test_plain_card_never_beats_a_trump(self):
        self.assertFalse(beats(parse_card("AS"), parse_card("6H"), "H"))

    def test_trump_beaten_only_by_higher_trump(self):
        self.assertTrue(beats(parse_card("KH"), parse_card("QH"), "H"))
        self.assertFalse(beats(parse_card("QH"), parse_card("KH"), "H"))

    def test_off_suit_plain_cards_do_not_interact(self):
        self.assertFalse(beats(parse_card("AS"), parse_card("6D"), "H"))

    def test_deck_is_thirty_six_distinct_cards(self):
        deck = full_deck()
        self.assertEqual(len(deck), 36)
        self.assertEqual(len(set(deck)), 36)
        self.assertEqual(min(c.rank for c in deck), 6)
        self.assertEqual(max(c.rank for c in deck), 14)

    def test_additions_must_match_a_rank_in_play(self):
        match, _ = _duel(1)
        match.table = Table()
        match.table.add_attack(Card(9, "S"))
        match.table.add_defence(0, Card(11, "S"))
        match.sides["player"].hand = [Card(9, "D"), Card(11, "C"), Card(7, "H")]
        # The defender needs cards, or the cap alone forbids every addition.
        match.sides["enemy"].hand = [Card(r, "C") for r in (6, 7, 8, 10)]
        legal = match.legal_additions("player", "enemy")
        self.assertIn(Card(9, "D"), legal)   # matches the attack card
        self.assertIn(Card(11, "C"), legal)  # matches the card that beat it
        self.assertNotIn(Card(7, "H"), legal)

    def test_attack_cap_never_exceeds_defender_hand(self):
        match, _ = _duel(2)
        match.table = Table()
        match.table.add_attack(Card(9, "S"))
        match.sides["enemy"].hand = [Card(10, "S")]
        match.sides["player"].hand = [Card(9, c) for c in "HDC"]
        # One card already down plus a single-card defender caps the bout at 2.
        self.assertEqual(match._attack_cap("enemy"), 2)

    def test_pickup_moves_every_table_card_into_the_defender_hand(self):
        match, _ = _duel(3)
        match.table = Table()
        # Trump is hearts, so a lone six of diamonds cannot answer the ace.
        match.sides["player"].hand = [Card(14, "S")]
        match.sides["player"].talon = []
        match.sides["enemy"].hand = [Card(6, "D")]
        match.sides["enemy"].talon = []
        match.attacker = "player"
        record = match.play_bout()
        self.assertEqual(record.outcome, BOUT_TAKEN)
        self.assertIn(Card(14, "S"), match.sides["enemy"].hand)
        self.assertEqual(record.unbeaten_taken, 1)

    def test_beaten_bout_discards_and_hands_over_the_attack(self):
        match, _ = _duel(4)
        match.table = Table()
        match.sides["player"].hand = [Card(6, "S")]
        match.sides["player"].talon = []
        match.sides["enemy"].hand = [Card(7, "S")]
        match.sides["enemy"].talon = []
        match.attacker = "player"
        record = match.play_bout()
        self.assertEqual(record.outcome, BOUT_BEATEN)
        self.assertEqual(len(match.table), 0)
        self.assertEqual(match.attacker, "enemy")

    def test_a_match_always_terminates_and_reports_a_result(self):
        for seed in range(60):
            _, result = _duel(seed)
            self.assertIn(result.winner, ("player", "enemy", None))
            self.assertGreater(result.bouts, 0)


class TestDeterminism(unittest.TestCase):
    def test_same_seed_gives_the_same_match(self):
        for seed in (1, 17, 99):
            self.assertEqual(_duel(seed)[1].winner, _duel(seed)[1].winner)

    def test_rng_matches_the_swift_generator_contract(self):
        # splitmix64 remaps a zero seed rather than locking at zero.
        self.assertNotEqual(SeededRNG(0).next(), 0)
        self.assertEqual([SeededRNG(5).next() for _ in range(3)],
                         [SeededRNG(5).next() for _ in range(3)])

    def test_runs_are_reproducible(self):
        a = [play_run(s, "typical", "balanced").depth_reached for s in range(40)]
        b = [play_run(s, "typical", "balanced").depth_reached for s in range(40)]
        self.assertEqual(a, b)

    def test_no_relics_is_identical_to_an_empty_relic_set(self):
        """Relic plumbing must not perturb the vanilla game."""
        for seed in range(120):
            plain = _duel(seed, relics=None)[1]
            empty = _duel(seed, relics=RelicSet([]))[1]
            self.assertEqual((plain.winner, plain.bouts), (empty.winner, empty.bouts))


class TestBalance(unittest.TestCase):
    """Audits of the design, not the code. These fail when the game is wrong.

    Deliberately loose. They exist to catch the failures this prototype
    actually hit — a relic that trivialises the run, a skill axis pointing the
    wrong way, a resource that never binds — not to freeze today's tuning.
    """

    SEEDS = 150

    def _depth(self, skill="typical", relics=None, config=None):
        return statistics.mean(
            play_run(s, skill, "balanced", config, relics).depth_reached
            for s in range(self.SEEDS)
        )

    def test_skill_ladder_points_the_right_way(self):
        sharp, typical, tired = (self._depth(k) for k in ("sharp", "typical", "tired"))
        self.assertGreater(sharp, typical)
        self.assertGreater(typical, tired)

    def test_the_gauntlet_is_neither_a_walkover_nor_a_wall(self):
        depths = [play_run(s, "typical", "balanced").depth_reached for s in range(self.SEEDS)]
        clear = sum(1 for d in depths if d >= RunConfig().encounters) / len(depths)
        self.assertGreater(clear, 0.05, "a typical player almost never clears the run")
        self.assertLess(clear, 0.60, "a typical player clears too easily")

    def test_no_relic_trivialises_the_run(self):
        """The audit that caught Sharpshooter at a 97% clear rate."""
        base = self._depth()
        for key in sorted(CATALOGUE):
            delta = self._depth(relics=[key]) - base
            self.assertLess(delta, 2.0, f"{CATALOGUE[key].name} is worth {delta:+.2f} encounters")

    def test_no_relic_is_a_downgrade(self):
        """A relic you would rather not have picked up is a bug, not a choice."""
        base = self._depth()
        for key in sorted(CATALOGUE):
            delta = self._depth(relics=[key]) - base
            self.assertGreater(delta, -0.75, f"{CATALOGUE[key].name} is worth {delta:+.2f} encounters")

    def test_health_actually_binds(self):
        """A resource nobody runs out of makes every relic touching it dead."""
        scarce = self._depth(config=RunConfig(starting_health=4))
        plenty = self._depth(config=RunConfig(starting_health=30))
        self.assertGreater(plenty - scarce, 0.5,
                           "starting health barely changes the run; wounds are decorative")


if __name__ == "__main__":
    unittest.main(verbosity=2)
