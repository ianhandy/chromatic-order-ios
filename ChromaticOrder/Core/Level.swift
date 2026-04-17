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
    // Tier labels shifted up one slot to match player perception —
    // the old "Mild" (lv 7-9) consistently got rated as a Medium feel
    // by playtesters, so the whole scale moves: Mild → Medium,
    // Medium → Hard, Hard → Expert, Expert → Master. Generator config
    // per level untouched; only the label the player sees changes.
    static let labels = ["Trivial", "Easy", "Medium", "Hard", "Expert", "Master"]
    static let hexes  = ["#2a9d4e", "#38a832", "#b8a400", "#d97700", "#cc3333", "#900"]
}

func levelTier(_ level: Int) -> LevelTierInfo {
    let i = min(max(0, level - 1) / 3, Tiers.labels.count - 1)
    return LevelTierInfo(index: i, label: Tiers.labels[i], colorHex: Tiers.hexes[i])
}

// Per-step OKLCh range for the primary-role channel. Matches the JS
// ranges exactly; 3 levels per tier, parameters shift gradually.
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
    // Tier 1: Trivial (lv 1-3). 1 channel, obvious steps, anchored endpoint.
    if level <= 3 {
        let t = Double(level - 1) / 2.0
        let hi = 0.10 - 0.005 * t
        let lo = 0.06 - 0.005 * t
        let hHi = 32 - 2 * t, hLo = 22 - 2 * t
        return LevelConfig(
            channelCount: 1,
            ranges: .init(L: lo...hi, c: lo...(hi - 0.01), h: hLo...hHi),
            anchorEndpoints: 1
        )
    }
    if level <= 6 {
        return LevelConfig(
            channelCount: Util.chance(0.85) ? 1 : 2,
            ranges: .init(L: 0.05...0.09, c: 0.05...0.08, h: 20...30),
            anchorEndpoints: 0
        )
    }
    if level <= 9 {
        return LevelConfig(
            channelCount: Util.chance(0.65) ? 1 : 2,
            ranges: .init(L: 0.045...0.08, c: 0.045...0.07, h: 17...27),
            anchorEndpoints: 0
        )
    }
    if level <= 12 {
        return LevelConfig(
            channelCount: Util.chance(0.55) ? 2 : 1,
            ranges: .init(L: 0.04...0.07, c: 0.04...0.06, h: 13...22),
            anchorEndpoints: 0
        )
    }
    if level <= 15 {
        return LevelConfig(
            channelCount: Util.chance(0.45) ? 3 : 2,
            ranges: .init(L: 0.03...0.055, c: 0.03...0.05, h: 10...18),
            anchorEndpoints: 0
        )
    }
    return LevelConfig(
        channelCount: Util.chance(0.5) ? 3 : 2,
        ranges: .init(L: 0.022...0.045, c: 0.022...0.045, h: 8...15),
        anchorEndpoints: 0
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
        : active.randomElement()!
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
    extrapProx: Double = 0
) -> Int {
    let totalCells = gradients.reduce(0) { $0 + $1.len }
    let freeRatio = Double(bankCount) / Double(max(totalCells, 1))
    let chScore: Double = channelCount == 1 ? 0 : channelCount == 2 ? 0.4 : 1.0

    var totalStep = 0.0
    var stepN = 0
    for g in gradients {
        for i in 1..<g.colors.count {
            totalStep += OK.dist(g.colors[i - 1], g.colors[i])
            stepN += 1
        }
    }
    let avgStep = stepN > 0 ? totalStep / Double(stepN) : 20
    let stepScore = Util.clamp(1.0 - (avgStep - 2) / 18, 0, 1)

    let pairProxScore = Util.clamp(pairProx / 6, 0, 1.5)
    let extrapProxScore = Util.clamp(extrapProx / 20, 0, 1.5)
    let primaryChScore: Double = primary == .c ? 1.0 : primary == .L ? 0.7 : 0

    let raw =
        freeRatio * 1.0 +
        chScore * 1.5 +
        stepScore * 1.5 +
        pairProxScore * 2.5 +
        extrapProxScore * 0.8 +
        primaryChScore * 1.5 +
        max(0, Double(gradients.count - 2)) * 0.5
    return Util.clamp(Int(raw.rounded()), 1, 10)
}
