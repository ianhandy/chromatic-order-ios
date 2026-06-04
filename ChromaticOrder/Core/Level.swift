//  Level tiers, per-level config, channel+role assignment, and difficulty
//  scoring. Swift port of src/level.js.

import Foundation

enum Channel: String, Hashable, CaseIterable { case L, c, h }
enum ChannelRole: String { case primary, secondary, tertiary }

struct LevelTierInfo {
    let index: Int
    let label: String
    let colorHex: String
}

enum Tiers {
    // Five tiers, five levels each — the curve was stretched from the
    // old 3-levels-per-tier pacing so each step up is gentler. The old
    // "Master" tier (lv 16+: 10 gradients, 8-15° hue, smallest ΔE) was
    // near-impossible, so it's gone entirely: Expert is now the
    // sustained ceiling and levels past 21 plateau at fair-but-hard
    // Expert parameters rather than ramping into the wall.
    static let labels = ["Trivial", "Easy", "Medium", "Hard", "Expert"]
    static let hexes  = ["#2a9d4e", "#38a832", "#b8a400", "#d97700", "#cc3333"]
}

func levelTier(_ level: Int) -> LevelTierInfo {
    let i = min(max(0, level - 1) / 5, Tiers.labels.count - 1)
    return LevelTierInfo(index: i, label: Tiers.labels[i], colorHex: Tiers.hexes[i])
}

// Per-step OKLCh range for the primary-role channel. Parameters now
// interpolate continuously from level 1 to the Expert ceiling at level
// 21 so the difficulty ramp is smooth rather than stepping per 3-level
// tier.
struct LevelRanges {
    let L: ClosedRange<Double>
    let c: ClosedRange<Double>
    let h: ClosedRange<Double>
}

struct LevelConfig {
    let channelCount: Int
    let ranges: LevelRanges
    let anchorEndpoints: Int  // 1 = lock first endpoint of each gradient
}

func levelConfig(_ level: Int) -> LevelConfig {
    // Continuous difficulty ramp. `f` runs 0 → 1 from level 1 to the
    // Expert ceiling at level 21+; past that it stays clamped at 1, so
    // the curve plateaus at fair-but-hard Expert parameters instead of
    // pushing into the old Master band.
    //
    // The easy anchor (f=0) is the old Trivial start. The hard anchor
    // (f=1) is the old EXPERT (lv 13-15) values — deliberately NOT the
    // old Master band (L 0.022, hue 8°), which is what made the top
    // tier near-impossible. Hue floor stays above the perceptual-
    // collapse zone the whole way up.
    let f = Util.clamp(Double(level - 1) / 20.0, 0, 1)
    func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }

    let lLo = lerp(0.06, 0.030), lHi = lerp(0.10, 0.055)
    let cLo = lerp(0.05, 0.030), cHi = lerp(0.09, 0.050)
    let hLo = lerp(34, 10),      hHi = lerp(50, 18)

    // Channel count steps up gradually: a single channel through all of
    // Trivial, with 2- and (late) 3-channel puzzles phasing in. Even at
    // the Expert ceiling 3 channels is only a coin flip, never forced.
    let channelCount: Int
    switch level {
    case ...5:    channelCount = 1
    case 6...10:  channelCount = Util.chance(0.85) ? 1 : 2
    case 11...15: channelCount = Util.chance(0.55) ? 1 : 2
    case 16...20: channelCount = Util.chance(0.55) ? 2 : (Util.chance(0.5) ? 3 : 1)
    default:      channelCount = Util.chance(0.5) ? 2 : 3
    }

    return LevelConfig(
        channelCount: channelCount,
        // Anchor an endpoint through the whole Trivial tier so the very
        // first levels always hand the player a fixed reference cell.
        ranges: .init(L: lLo...lHi, c: cLo...cHi, h: hLo...hHi),
        anchorEndpoints: level <= 5 ? 1 : 0
    )
}

struct ChannelAssignment {
    let active: [Channel]               // sorted, length == count
    let roleFor: [Channel: ChannelRole] // one primary, rest secondary/tertiary
    var primary: Channel { roleFor.first(where: { $0.value == .primary })!.key }
}

// Pick `count` channels and assign primary/secondary/tertiary roles. A
// `huePrimaryBias` forces hue active AND primary with that probability.
func pickChannelsAndRoles(count: Int, huePrimaryBias: Double = 0.5) -> ChannelAssignment {
    let forceHue = Util.chance(huePrimaryBias)
    var active: [Channel]
    if forceHue {
        active = [.h]
        if count > 1 {
            active.append(contentsOf: Util.shuffle([.L, .c]).prefix(count - 1))
        }
    } else {
        active = Array(Util.shuffle(Channel.allCases).prefix(count))
    }
    let roles: [ChannelRole] = [.primary, .secondary, .tertiary]
    var roleFor: [Channel: ChannelRole] = [:]
    let primary: Channel = forceHue && active.contains(.h)
        ? .h
        : Util.randomElement(active)!
    roleFor[primary] = .primary
    let rest = Util.shuffle(active.filter { $0 != primary })
    for (i, ch) in rest.enumerated() { roleFor[ch] = roles[i + 1] }
    return ChannelAssignment(active: active.sorted(by: { $0.rawValue < $1.rawValue }),
                             roleFor: roleFor)
}

// Difficulty 1..10. Weights tuned from playtest feedback on the web
// version — factors scale to 0-1 except pair/extrap which saturate at 1.5.
func scoreDifficulty(
    gradients: [PuzzleGradient],
    bankCount: Int,
    channelCount: Int,
    primary: Channel,
    pairProx: Double = 0,
    extrapProx: Double = 0,
    mode: CBMode = .none
) -> Int {
    let chScore: Double = channelCount == 1 ? 0 : channelCount == 2 ? 0.4 : 1.0

    // Direct work measure: how many pieces the player has to place.
    // Replaces the old `freeRatio` + `countBonus` pair. bankCount is
    // the unambiguous signal of "how much arranging left to do."
    let bankSizeScore = Util.clamp(Double(bankCount) / 20, 0, 1.5)

    // Hint credits — cells the player doesn't have to figure out.
    // Locked cells are direct hints; shared intersections pin a single
    // color across two gradients at once. Count intersection cells
    // uniquely (a cell shared by 2 gradients appears twice in the flat
    // per-gradient list).
    var lockedUniqueKeys: Set<Int> = []
    var intersectionUniqueKeys: Set<Int> = []
    for g in gradients {
        for spec in g.cells {
            let key = spec.r * 64 + spec.c
            if spec.locked { lockedUniqueKeys.insert(key) }
            if spec.isIntersection { intersectionUniqueKeys.insert(key) }
        }
    }
    let lockHintScore = Util.clamp(Double(lockedUniqueKeys.count) / 10, 0, 1.5)
    let intersectionScore = Util.clamp(Double(intersectionUniqueKeys.count) / 4, 0, 1.0)

    var totalStep = 0.0
    var stepN = 0
    for g in gradients {
        for i in 1..<g.colors.count {
            // Use CB-aware distance so CB players' step magnitudes
            // reflect what they can actually see.
            totalStep += OK.dist(g.colors[i - 1], g.colors[i], mode: mode)
            stepN += 1
        }
    }
    let avgStep = stepN > 0 ? totalStep / Double(stepN) : 20
    let stepScore = Util.clamp(1.0 - (avgStep - 2) / 18, 0, 1)

    // Primary-channel weight. Hue used to be 0 on the assumption that
    // humans distinguish hues well — but that's only true when the
    // hue RANGE is wide. "All red" puzzles (narrow-hue, same-chroma)
    // are actually the hardest to discriminate. Hue now weights AT
    // LEAST as much as chroma, and scales up further when the
    // gradient's hue span is narrow.
    let primaryChBase: Double = primary == .c ? 1.0 : primary == .L ? 0.7 : 1.1
    // Hue-span bonus: measure max-min hue across every gradient's
    // color list (in degrees) and reward narrow spans with extra
    // difficulty. Under ~30° spans ~1.0 of extra weight; >~120° = 0.
    var hueBonus: Double = 0
    if primary == .h {
        let hues = gradients.flatMap { g in g.colors.map { $0.h } }
        if hues.count >= 2 {
            let lo = hues.min() ?? 0
            let hi = hues.max() ?? 0
            let span = hi - lo
            // Clamp-and-invert: narrower = harder.
            hueBonus = Util.clamp(1.0 - (span - 25) / 100, 0, 1.0)
        }
    }
    let primaryChScore = primaryChBase + hueBonus

    // Confusion score: how likely two gradients' colors get mistaken
    // for each other. Combines pairProx (cell-pair proximity) and
    // extrapProx (extended-line crossings) into one saturating term.
    let confusionScore = Util.clamp(pairProx / 6 + extrapProx / 20, 0, 1.5)

    let raw =
        bankSizeScore * 3.0
      + stepScore * 3.0
      + confusionScore * 4.5
      + chScore * 1.5
      + primaryChScore * 1.5
      - lockHintScore * 1.5            // pre-revealed cells reduce work
      - intersectionScore * 0.5        // shared cells propagate info
    return Util.clamp(Int(raw.rounded()), 1, 10)
}
