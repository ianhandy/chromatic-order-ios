//  Test-harness filter. Deliberately makes a board harder to read so an
//  automated playtester (or a human one) can measure how much perceptual
//  headroom a level actually has, rather than guessing from the ΔE
//  numbers the generator reports.
//
//  Two independent knobs:
//
//  • similarity: pulls every puzzle color toward a single reference
//    color before it is drawn. Because the pull is an affine contraction
//    in OKLab (where ΔE is plain Euclidean distance), a similarity of
//    `s` scales EVERY ΔE on the board by exactly (1 - s). That exactness
//    is the whole point: the playtester sweeps `s` upward and reads the
//    failure point off as "this level survives down to ΔE × (1 - s)".
//    Nonlinear tricks (per-cell desaturation, blending in sRGB) would
//    scale different pairs by different amounts and the sweep would
//    measure nothing.
//
//  • sameThreshold: how close two colors have to be before the game's
//    judging treats them as the same color. Raising it lets the tester
//    ask "would this level still be solvable if the player only had to
//    get within ΔE 6?" without touching the generator.
//
//  Both are gated behind `enabled`, which is off by default and guards
//  early everywhere: with it off, this file changes nothing about how
//  the game looks or scores.

import Foundation

struct TestingFilter {
    /// Master switch. Off = every method here is a pass-through to the
    /// behavior the game had before this type existed.
    var enabled: Bool = false
    /// 0 = board looks normal, 0.9 = every cell looks nearly identical.
    var similarity: Double = 0
    /// ΔE below which two colors count as the same color when judging a
    /// placement. 2 reproduces `OK.equal`'s own JND cutoff, so the
    /// default value changes no verdicts.
    var sameThreshold: Double = 2
    /// The color everything is pulled toward. Owned by the caller and
    /// set once per board (the mean of that board's solution colors),
    /// because recomputing it per cell would move the target as the
    /// board changed and the contraction would never converge. nil (no board
    /// loaded yet) means there is nothing to compress toward, so
    /// `display` passes colors straight through.
    var reference: OKLCh? = nil

    /// Slider bounds, shared by the settings sheet and the clamps below
    /// so a hand-edited or older persisted value can't push the filter
    /// somewhere the UI can't express.
    static let similarityRange: ClosedRange<Double> = 0...0.95
    static let thresholdRange: ClosedRange<Double> = 0.5...12

    /// The inert filter. Handy as a default and as the negative control
    /// in tests.
    static let off = TestingFilter()

    /// What the player should actually see for a given puzzle color.
    /// Compresses toward `reference` in OKLab so all differences shrink
    /// by the same factor.
    func display(_ color: OKLCh) -> OKLCh {
        guard enabled, similarity > 0, let reference else { return color }
        let keep = 1 - Self.similarityRange.clamping(similarity)
        let ref = OK.toLab(reference)
        let lab = OK.toLab(color)
        return OK.fromLab(
            L: ref.L + keep * (lab.L - ref.L),
            a: ref.a + keep * (lab.a - ref.a),
            b: ref.b + keep * (lab.b - ref.b)
        )
    }

    /// "Do these two colors count as the same color?", the question the
    /// game asks when it decides whether a placement is right. Disabled
    /// defers to `OK.equal` rather than reimplementing it, so the two
    /// can't drift apart.
    func same(_ a: OKLCh, _ b: OKLCh, mode: CBMode = .none) -> Bool {
        guard enabled else { return OK.equal(a, b, mode: mode) }
        return OK.dist(a, b, mode: mode) < Self.thresholdRange.clamping(sameThreshold)
    }

    /// Mean of a board's solution colors, averaged in OKLab because hue
    /// angles don't average (0° and 350° average to 175°, the opposite
    /// side of the wheel). Returns nil for an empty list (see
    /// `reference`).
    static func meanColor(of colors: [OKLCh]) -> OKLCh? {
        guard !colors.isEmpty else { return nil }
        var sumL = 0.0, sumA = 0.0, sumB = 0.0
        for color in colors {
            let lab = OK.toLab(color)
            sumL += lab.L; sumA += lab.a; sumB += lab.b
        }
        let n = Double(colors.count)
        return OK.fromLab(L: sumL / n, a: sumA / n, b: sumB / n)
    }
}

private extension ClosedRange where Bound == Double {
    func clamping(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
