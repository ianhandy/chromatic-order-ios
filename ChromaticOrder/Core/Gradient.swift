//  Gradient step math — per-axis step caps, constrained-gradient builder,
//  gamut-safe stepping. Swift port of src/gradient.js (trimmed: we only
//  need the pieces actually used by Generate for the cellular grower).

import Foundation

struct StepCaps {
    struct Axis {
        let soft: Double
        let hard: Double
    }
    static let h = Axis(soft: 50, hard: 70)         // degrees
    static let c = Axis(soft: 0.10, hard: 0.16)     // fractional chroma
    static let L = Axis(soft: 0.10, hard: 0.16)     // fractional lightness
}

// Pick a step delta for one axis given the role-scaled range. Sign is
// random unless `preferSign` is given (used to keep a gradient moving
// consistently in one direction once the first step is chosen).
func pickStep(range: ClosedRange<Double>,
              role: ChannelRole,
              preferSign: Double? = nil,
              hueAxis: Bool = false) -> Double {
    // Secondary/tertiary axes take a fraction of the primary range so
    // they read as "variation along the gradient" rather than a
    // co-equal channel. Matches the web generator's heuristic.
    let scale: Double = role == .primary ? 1.0
                      : role == .secondary ? 0.6
                      : 0.35
    let mag = Util.randRange(range.lowerBound, range.upperBound) * scale
    let sign = preferSign ?? Util.randSign()
    let raw = mag * sign
    // Cap at the hard limit for the axis, so a random high roll can't
    // blow past a perceptually jarring jump.
    let hard = hueAxis ? StepCaps.h.hard
             : (range.upperBound > 1 ? StepCaps.h.hard
                : (range.upperBound > 0.2 ? StepCaps.c.hard : StepCaps.L.hard))
    return max(-hard, min(hard, raw))
}

// Apply one step onto an OKLCh color along the given channel.
func applyStep(_ color: OKLCh, channel: Channel, delta: Double) -> OKLCh {
    switch channel {
    case .L: return OKLCh(L: color.L + delta, c: color.c, h: color.h)
    case .c: return OKLCh(L: color.L, c: color.c + delta, h: color.h)
    case .h: return OKLCh(L: color.L, c: color.c, h: OK.normH(color.h + delta))
    }
}

// Would-be next color from stepping all active channels. Used by Generate
// to walk a gradient cell by cell.
struct StepPlan {
    // Per-active-channel signed step magnitude. Fixed for the life of the
    // gradient once chosen, so all cells advance consistently.
    var deltas: [Channel: Double]
}

func makeStepPlan(ranges: LevelRanges,
                  assign: ChannelAssignment) -> StepPlan {
    var deltas: [Channel: Double] = [:]
    // Pick ONE sign per channel so the gradient is monotone in that axis.
    for ch in assign.active {
        let role = assign.roleFor[ch] ?? .secondary
        let range: ClosedRange<Double>
        switch ch {
        case .L: range = ranges.L
        case .c: range = ranges.c
        case .h: range = ranges.h
        }
        deltas[ch] = pickStep(range: range, role: role, hueAxis: ch == .h)
    }
    return StepPlan(deltas: deltas)
}

// Advance one cell along the gradient using the fixed step plan. Returns
// nil if the next color would leave the usable perceptual band — the
// grower treats this as a dead-end.
func stepColor(from color: OKLCh, using plan: StepPlan) -> OKLCh? {
    var next = color
    for (ch, delta) in plan.deltas {
        next = applyStep(next, channel: ch, delta: delta)
    }
    return OK.inUsableBand(next) ? next : nil
}
