//  Central catalog of level-generation rules. High-level knobs that
//  govern how the procedural generator behaves — attempt counts,
//  retry strategy, difficulty scoring weights, intersection /
//  sparsity / uniqueness guards. Edit here to reshape generator
//  behavior without grepping Generate.swift for magic numbers.
//
//  Generate.swift should reference these constants by name. Values
//  are plain Swift so the file is importable from test tools.

import Foundation

enum LevelGeneratorRules {

    // MARK: – Retry strategy

    enum Retry {
        /// Attempts per regeneration round. Each attempt runs one
        /// full growth + validation pass; on failure we try again.
        static let attemptsPerRound: Int = 500
        /// How many full rounds of `attemptsPerRound` attempts we
        /// burn before accepting the handcrafted fallback puzzle.
        /// 5 × 500 = 2,500 total tries for stubborn levels.
        static let fallbackAfterRounds: Int = 5
    }

    // MARK: – Lock / reveal strategy

    enum Locks {
        /// Fraction of free cells above which Guard 2 rejects the
        /// layout and forces regeneration (too many locked cells
        /// left = puzzle has too few things for the player to do).
        static let maxFractionOfFreeCells: Double = 0.40
        /// When the uniqueness solver can't find a disambiguator,
        /// Guard 4's mask enumerator adds locks greedily — pick the
        /// gradient whose bit=1 kills the most masks per lock added.
        /// This flag controls whether the greedy pass runs.
        static let useGreedyMinLock: Bool = true
    }

    // MARK: – Validators

    enum Validators {
        /// Force-lock any cell whose solution color equals another
        /// cell's within perceptual ΔE. Without this the puzzle has
        /// multiple solutions — the player can't tell the two cells
        /// apart from color alone.
        static let forceLockDuplicateColors: Bool = true
        /// Force-lock cells that are edge-adjacent to a DIFFERENT
        /// gradient without sharing an intersection (crossword-
        /// sparsity violation). Keeps sparse-adjacent layouts
        /// solvable by revealing the ambiguous cells at start.
        static let forceLockSparsityViolators: Bool = true
    }

    // MARK: – Daily puzzle

    enum Daily {
        /// Fixed challenge level used for the daily puzzle. Seed-
        /// based level rotation is paused until the higher-tier
        /// difficulty curve is dialed in.
        static let fixedLevel: Int = 10
    }

    // MARK: – Challenge progression

    enum ChallengeProgression {
        /// Number of solves required to advance one tier in
        /// challenge mode. Lower = faster climb.
        static let solvesPerLevel: Int = 2
        /// Number of consecutive no-heart-lost solves that earns
        /// an extra level skip on top of the normal progression.
        static let noHeartStreakForSkip: Int = 3
        /// Number of consecutive perfect solves that earns an
        /// extra level skip.
        static let perfectStreakForSkip: Int = 2
        /// Heart count granted at the start of a challenge run.
        static let startingHearts: Int = 3
    }

    // MARK: – Generator output ranges

    enum Output {
        /// Minimum cells across the shorter axis for any generated
        /// puzzle. Below this the puzzle feels too tight.
        static let minGridMinor: Int = 3
        /// Maximum cells across either axis. Above this the grid
        /// stops fitting comfortably on phones.
        static let maxGridAxis: Int = 11
    }
}
