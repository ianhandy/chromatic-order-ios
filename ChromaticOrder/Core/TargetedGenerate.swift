//  Targeted-difficulty generator — alternative to `generatePuzzle`.
//
//  Mirrors `src/targetedGenerate.js` on the `targeted-difficulty`
//  branch of the web repo. Use the web sampler (`npm run
//  sample:targeted -- --level N --count M`) to tune bands without
//  rebuilding the iOS app; once the numbers feel right, port them
//  here via the `BAND_WIDTH` / `TOLERANCE` constants below.
//
//  Gate: `kroma.dev.targetedGen` UserDefaults bool. Flip via:
//      UserDefaults.standard.set(true, forKey: "kroma.dev.targetedGen")
//  When enabled, `GameState` routes level generation through
//  `generateTargetedPuzzle` instead of the existing `generatePuzzle`.
//  No UI exposure yet — dev-only knob.

import Foundation

enum TargetedGen {
    /// Width of each level's difficulty band, in scaled score units.
    /// Higher = more intra-level variety; lower = tighter per-level
    /// feel at the cost of starvation at band edges.
    static let bandWidth: Int = 50
    /// Acceptance tolerance in scaled score units. A candidate is
    /// accepted when its score lands within ±tolerance of the rolled
    /// target. Matches the web prototype's default.
    static let tolerance: Int = 2
    /// Scale factor applied to raw (unclamped, unrounded) scores so
    /// the 0-15-ish continuous value becomes the integer band space.
    static let scoreScale: Double = 100
    /// Per-call attempt budget before the "closest-seen" fallback.
    static let maxAttempts: Int = 1500

    /// Returns `(lo, hi)` inclusive for the supplied level.
    static func band(for level: Int) -> (lo: Int, hi: Int) {
        let n = max(1, level)
        return ((n - 1) * bandWidth, n * bandWidth - 1)
    }

    /// Uniform random integer target inside the level's band.
    static func rollTarget(for level: Int) -> Int {
        let (lo, hi) = band(for: level)
        return Int.random(in: lo...hi)
    }

    /// Continuous, unclamped version of the 1-10 scorer used by
    /// `Level.swift`. Kept in parallel rather than shared so the
    /// player-visible "difficulty" int remains stable while this
    /// generator tunes against a finer-grained internal signal.
    static func rawScore(
        gradients: [PuzzleGradient],
        bankCount: Int,
        channelCount: Int,
        primary: Channel,
        pairProx: Double,
        extrapProx: Double,
        mode: CBMode
    ) -> Double {
        let totalCells = gradients.reduce(0) { $0 + $1.len }
        let freeRatio = Double(bankCount) / Double(max(totalCells, 1))
        let chScore: Double = channelCount == 1 ? 0 : channelCount == 2 ? 0.4 : 1.0

        var totalStep = 0.0
        var stepN = 0
        for g in gradients {
            for i in 1..<g.colors.count {
                totalStep += OK.dist(g.colors[i - 1], g.colors[i], mode: mode)
                stepN += 1
            }
        }
        let avgStep = stepN > 0 ? totalStep / Double(stepN) : 20
        let stepScore = Util.clamp(1.0 - (avgStep - 2) / 18, 0, 1)

        let pairProxScore = Util.clamp(pairProx / 6, 0, 1.5)
        let extrapProxScore = Util.clamp(extrapProx / 20, 0, 1.5)

        let primaryChBase: Double = primary == .c ? 1.0 : primary == .L ? 0.7 : 1.1
        var hueBonus: Double = 0
        if primary == .h {
            let hues = gradients.flatMap { g in g.colors.map { $0.h } }
            if hues.count >= 2 {
                let lo = hues.min() ?? 0
                let hi = hues.max() ?? 0
                let span = hi - lo
                hueBonus = Util.clamp(1.0 - (span - 25) / 100, 0, 1.0)
            }
        }
        let primaryChScore = primaryChBase + hueBonus

        let raw =
            freeRatio * 1.0 +
            chScore * 1.5 +
            // Parity with Level.swift's scoreDifficulty bump.
            stepScore * 3.0 +
            pairProxScore * 4.5 +
            extrapProxScore * 0.8 +
            primaryChScore * 1.5 +
            max(0, Double(gradients.count - 2)) * 0.5

        return raw * scoreScale
    }

    /// Score a built `Puzzle` using the same component math as the
    /// targeted generator's per-attempt ranker.
    static func rawScore(of puzzle: Puzzle, mode: CBMode = .none) -> Double {
        let bank = puzzle.bank.compactMap { $0 }.count
        return rawScore(
            gradients: puzzle.gradients,
            bankCount: bank,
            channelCount: puzzle.channelCount,
            primary: puzzle.primaryChannel,
            pairProx: puzzle.pairProx,
            extrapProx: puzzle.extrapProx,
            mode: mode
        )
    }
}

/// Drop-in alternative to `generatePuzzle`. Rolls a target in the
/// requested level's band, retries the existing grower until a
/// candidate's scaled raw score lands within `TargetedGen.tolerance`.
/// On budget exhaustion, returns the closest candidate seen rather
/// than invoking any handcrafted fallback.
func generateTargetedPuzzle(
    level: Int,
    config: GenConfig = GenConfig(),
    mode: CBMode = .none
) -> Puzzle {
    let target = TargetedGen.rollTarget(for: level)

    var best: Puzzle? = nil
    var bestDelta: Double = .infinity

    for _ in 0..<TargetedGen.maxAttempts {
        guard let puz = tryGeneratePuzzleAttempt(level: level, config: config)
        else { continue }
        let score = TargetedGen.rawScore(of: puz, mode: mode)
        let delta = abs(score - Double(target))
        if delta <= Double(TargetedGen.tolerance) {
            return puz
        }
        if delta < bestDelta {
            best = puz
            bestDelta = delta
        }
    }

    if let best = best { return best }

    // Extreme pathology — the grower never succeeded in the attempt
    // budget. Keep trying indefinitely, matching the generatePuzzle
    // contract of "always return a Puzzle, never fall back to a
    // canned layout".
    while true {
        if let puz = tryGeneratePuzzleAttempt(level: level, config: config) {
            return puz
        }
    }
}

/// Single-attempt hook delegates to the public `tryGrowOnce` in
/// Generate.swift so this file doesn't need to poke at the grower's
/// private internals.
private func tryGeneratePuzzleAttempt(level: Int, config: GenConfig) -> Puzzle? {
    return tryGrowOnce(level: level, config: config)
}
