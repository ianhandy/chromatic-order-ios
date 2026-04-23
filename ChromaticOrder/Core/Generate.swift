//  Cellular growth puzzle generator. Swift port of src/generate.js.
//
//  One seed cell + one seed color grows into a whole puzzle via
//  per-tick weighted decisions (branch vs extend vs close). All color
//  math is OKLCh / OKLab — distances are perceptual ΔE, so "these
//  cells look similar" matches the eye regardless of hue / L region.

import Foundation

// ─── config / tuning knobs ──────────────────────────────────────────

struct GenConfig {
    /// nil = let `levelHuePrimaryBias(level)` pick a level-appropriate
    /// default. Explicit doubles override that curve.
    var huePrimaryBias: Double? = nil
    var symmetryRate: Double = 0.0
    var endpointCenterBias: Double = 0.5
    var lengthDiversityBias: Double = 0.7
    var rangeScale: Double = 1.0
    var branchRate: Double = 0.55
    var closeRate: Double = 0.18
    var channelCountOverride: Int? = nil
    var anchorEndpointsOverride: Int? = nil
    var gradientCountOverride: Int? = nil
    /// Color-blindness model to build the puzzle under. All distance
    /// math (canExtend duplicate check, pairProx / extrapProx / stepΔE,
    /// uniqueness sweep) runs in this model's color space, so the
    /// puzzle it produces has perceivable step separation FOR THIS
    /// PLAYER. .none = default, normal-vision tuning.
    var cbMode: CBMode = .none
    /// Accessibility clamps — tighter than OK's default usable band.
    /// Seed + extension checks reject any color that leaves the
    /// player's chosen L/c window, so the resulting puzzle stays in
    /// a contrast-friendly space.
    var lClampMin: Double = OK.lMin
    var lClampMax: Double = OK.lMax
    var cClampMin: Double = OK.cMin
    var cClampMax: Double = OK.cMax
}

/// Per-config usable-band check. Supersedes OK.inUsableBand's static
/// defaults when the generator runs — lets the player shrink the
/// allowed L / c window (Accessibility → clamp luminance / saturation).
private func inBandForConfig(_ color: OKLCh, _ cfg: GenConfig) -> Bool {
    color.L >= cfg.lClampMin && color.L <= cfg.lClampMax
        && color.c >= cfg.cClampMin && color.c <= cfg.cClampMax
}

private func applyConfig(_ cfg: LevelConfig, _ dev: GenConfig) -> LevelConfig {
    let s = dev.rangeScale
    let scaled = LevelRanges(
        L: (cfg.ranges.L.lowerBound * s)...(cfg.ranges.L.upperBound * s),
        c: (cfg.ranges.c.lowerBound * s)...(cfg.ranges.c.upperBound * s),
        h: (cfg.ranges.h.lowerBound * s)...(cfg.ranges.h.upperBound * s))
    return LevelConfig(
        channelCount: dev.channelCountOverride ?? cfg.channelCount,
        ranges: scaled,
        anchorEndpoints: dev.anchorEndpointsOverride ?? cfg.anchorEndpoints)
}

private func defaultGradientCount(_ level: Int) -> Int {
    if level <= 3 { return 1 }      // Trivial
    if level <= 6 { return 2 }      // Easy
    if level <= 9 { return 3 }      // Mild
    if level <= 12 { return 5 }     // Medium
    if level <= 15 { return 7 }     // Hard
    return 10                       // Expert
}

private func wordLenFor(_ level: Int) -> (Int, Int) {
    if level <= 2 { return (3, 5) }
    if level <= 5 { return (3, 6) }
    if level <= 8 { return (4, 7) }
    return (4, 8)
}

private func pairProxCap(_ level: Int) -> Double? {
    switch level {
    case 1: return 0.3
    case 2: return 0.5
    case 3: return 0.9
    case 4: return 1.5
    case 5: return 2.5
    case 6: return 4
    case 7: return 6
    case 8: return 8
    case 9: return 11
    case 10: return 15
    case 11: return 19
    case 12: return 24
    case 13: return 30
    case 14: return 38
    case 15: return 48
    default: return nil
    }
}

/// True if any gradient's colors are perceptually palindromic:
/// `colors[i] ≈ colors[n-1-i]` under the given CB mode for every i
/// up to the midpoint. These puzzles are fundamentally ambiguous —
/// the forward and reversed arrangements look identical, and no lock
/// can save them (a locked endpoint at pos 0 has the same color as
/// the reversed-reading's pos 0). Generator-side code in `finalize`
/// already rejects these; the helper is exposed so the community-pool
/// injection path (which bypasses the generator entirely) can apply
/// the same filter to legacy liked puzzles captured before the check
/// existed.
func hasPalindromicGradient(_ gradients: [PuzzleGradient],
                            mode: CBMode = .none) -> Bool {
    for g in gradients where g.len >= 2 {
        var mirror = true
        for i in 0..<(g.len / 2) where !OK.equal(g.colors[i],
                                                 g.colors[g.len - 1 - i],
                                                 mode: mode) {
            mirror = false
            break
        }
        if mirror { return true }
    }
    return false
}

/// Inclusive difficulty band `scoreDifficulty` (1–10) must land inside
/// for a given zen/challenge level. tryGrow rejects any layout whose
/// computed difficulty falls outside this window and retries, so
/// Easy levels can't ship Medium-feel puzzles (cap was too loose) and
/// Master can't ship Medium-feel ones either (no floor before). Bands
/// overlap by one step at adjacent tier boundaries — the shared
/// difficulty value lives in whichever tier the level belongs to, and
/// the overlap gives the grower enough room to converge within 2,500
/// attempts before falling back.
private func levelDifficultyBand(_ level: Int) -> ClosedRange<Int> {
    switch level {
    case 1...3:    return 1...2    // Trivial
    case 4...6:    return 2...3    // Easy
    case 7...9:    return 3...5    // Medium
    case 10...12:  return 5...7    // Hard
    case 13...15:  return 7...9    // Expert
    default:       return 8...10   // Master
    }
}

// Player feedback at lv 4-5 challenge mode flagged "hue-only on
// constant L/C" puzzles as feeling cheap against the timer. Lower
// hue-primary bias at the easy end so L or c take the primary role
// more often; ramp hue dominance back in for Expert / Master.
private func levelHuePrimaryBias(_ level: Int) -> Double {
    switch level {
    case ...3: return 0.30
    case 4...6: return 0.25
    case 7...9: return 0.50
    case 10...12: return 0.65
    case 13...15: return 0.75
    default: return 0.85
    }
}

private func pickSeedColor(cfg: GenConfig) -> OKLCh {
    // Stay central within the player's clamped band so the gradient
    // has room to drift in both directions before hitting a wall. A
    // 40%-70% band inside the clamp range works for both default and
    // narrow setups.
    let lMid = cfg.lClampMin + (cfg.lClampMax - cfg.lClampMin) * 0.4
    let lSpan = (cfg.lClampMax - cfg.lClampMin) * 0.3
    let cMid = cfg.cClampMin + (cfg.cClampMax - cfg.cClampMin) * 0.4
    let cSpan = (cfg.cClampMax - cfg.cClampMin) * 0.45
    return OKLCh(
        L: lMid + Util.randDouble(in: 0..<lSpan),
        c: cMid + Util.randDouble(in: 0..<cSpan),
        h: Util.randDouble(in: 0..<360)
    )
}

private func pickStepDeltas(_ assign: ChannelAssignment, _ ranges: LevelRanges) -> [Channel: Double] {
    var deltas: [Channel: Double] = [.L: 0, .c: 0, .h: 0]
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
    return deltas
}

// ─── working gradient (mutable during growth) ───────────────────────

private final class GrowGrad {
    let id: Int
    let dir: Direction
    let originR: Int
    let originC: Int
    var dL: Double
    var dC: Double
    var dH: Double
    var minPos: Int = 0
    var maxPos: Int = 0
    var colors: [Int: OKLCh]        // pos → color
    var status: String = "growing"  // "growing" | "closed"

    init(id: Int, dir: Direction, originR: Int, originC: Int,
         dL: Double, dC: Double, dH: Double, seed: OKLCh) {
        self.id = id
        self.dir = dir
        self.originR = originR
        self.originC = originC
        self.dL = dL; self.dC = dC; self.dH = dH
        self.colors = [0: seed]
    }

    var length: Int { maxPos - minPos + 1 }

    func cellOf(_ pos: Int) -> (r: Int, c: Int) {
        switch dir {
        case .h: return (originR, originC + pos)
        case .v: return (originR + pos, originC)
        }
    }

    func colorAt(_ pos: Int) -> OKLCh {
        let origin = colors[0]!
        return OKLCh(L: origin.L + dL * Double(pos),
                     c: origin.c + dC * Double(pos),
                     h: OK.normH(origin.h + dH * Double(pos)))
    }
}

// Working cell (mutable during growth). Keyed by "r,c".
private struct GrowCell {
    var color: OKLCh
    var gradIds: [Int]
}

// ─── extension / branching ──────────────────────────────────────────

private func canExtend(_ g: GrowGrad,
                       dir: String,          // "forward" | "backward"
                       gridW: Int, gridH: Int,
                       cells: [String: GrowCell],
                       mode: CBMode,
                       cfg: GenConfig) -> Bool {
    let nextPos = dir == "forward" ? g.maxPos + 1 : g.minPos - 1
    let (r, c) = g.cellOf(nextPos)
    if r < 0 || r >= gridH || c < 0 || c >= gridW { return false }
    let nextColor = g.colorAt(nextPos)
    // Accessibility clamps — check against the player's narrowed
    // band, not the fixed OK defaults.
    if !inBandForConfig(nextColor, cfg) { return false }
    let key = "\(r),\(c)"
    if cells[key] != nil { return false }
    // Crossword sparsity — reject if any edge-neighbor belongs to a
    // different gradient with no shared intersection.
    let nbrs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    for (dr, dc) in nbrs {
        let nr = r + dr, nc = c + dc
        if nr < 0 || nr >= gridH || nc < 0 || nc >= gridW { continue }
        if let nCell = cells["\(nr),\(nc)"] {
            if !nCell.gradIds.contains(g.id) { return false }
        }
    }
    // No cross-gradient color duplicates (ΔE < 2 == unsolvable). Under
    // a CB mode, this equality test runs in the player's perception,
    // so colors that happen to collapse only under their vision are
    // also rejected.
    for (_, cell) in cells {
        if cell.gradIds.contains(g.id) { continue }
        if OK.equal(cell.color, nextColor, mode: mode) { return false }
    }
    return true
}

private func commitExtend(_ g: GrowGrad,
                          dir: String,
                          cells: inout [String: GrowCell]) {
    let nextPos = dir == "forward" ? g.maxPos + 1 : g.minPos - 1
    let nextColor = g.colorAt(nextPos)
    let (r, c) = g.cellOf(nextPos)
    g.colors[nextPos] = nextColor
    if dir == "forward" { g.maxPos = nextPos } else { g.minPos = nextPos }
    let key = "\(r),\(c)"
    if var existing = cells[key] {
        existing.gradIds.append(g.id)
        cells[key] = existing
    } else {
        cells[key] = GrowCell(color: nextColor, gradIds: [g.id])
    }
}

private struct BranchSeed {
    let key: String
    let r: Int
    let c: Int
    let posInG: Int
    let g: GrowGrad
    let score: Double
}

private func pickBranchSeed(_ cells: [String: GrowCell],
                            _ gradients: [Int: GrowGrad],
                            _ dev: GenConfig) -> BranchSeed? {
    let eb = dev.endpointCenterBias
    var candidates: [BranchSeed] = []
    for (key, cell) in cells {
        if cell.gradIds.count != 1 { continue }
        let parts = key.split(separator: ",").map { Int($0)! }
        let r = parts[0], c = parts[1]
        guard let g = gradients[cell.gradIds[0]] else { continue }
        let posInG = g.dir == .h ? c - g.originC : r - g.originR
        var score = 1.0
        if posInG == g.minPos || posInG == g.maxPos { score += eb * 3 }
        let len = g.length
        if len % 2 == 1 && posInG == (g.minPos + g.maxPos) / 2 { score += eb * 3 }
        candidates.append(BranchSeed(key: key, r: r, c: c, posInG: posInG, g: g, score: score))
    }
    if candidates.isEmpty { return nil }
    let total = candidates.reduce(0) { $0 + $1.score }
    var pick = Util.randDouble(in: 0..<total)
    for x in candidates {
        pick -= x.score
        if pick < 0 { return x }
    }
    return candidates.last
}

private func tryBranch(cells: inout [String: GrowCell],
                       gradients: inout [Int: GrowGrad],
                       assign: ChannelAssignment,
                       ranges: LevelRanges,
                       dev: GenConfig,
                       gridW: Int, gridH: Int,
                       newId: Int) -> GrowGrad? {
    guard let seed = pickBranchSeed(cells, gradients, dev) else { return nil }
    let existing = seed.g
    let newDir: Direction = existing.dir == .h ? .v : .h

    let dL: Double, dC: Double, dH: Double
    let sameDir = gradients.values.filter { $0.dir == newDir }
    if Util.chance(dev.symmetryRate), let src = Util.randomElement(sameDir) {
        dL = -src.dL; dC = -src.dC; dH = -src.dH
    } else {
        let d = pickStepDeltas(assign, ranges)
        dL = d[.L] ?? 0; dC = d[.c] ?? 0; dH = d[.h] ?? 0
    }

    let newGrad = GrowGrad(id: newId, dir: newDir,
                           originR: seed.r, originC: seed.c,
                           dL: dL, dC: dC, dH: dH, seed: seed.g.colorAt(seed.posInG))
    // Tentatively add newGrad's id to branch cell so adjacency check in
    // canExtend treats the branch cell as same-grad. Rolled back on failure.
    if var sc = cells[seed.key] {
        sc.gradIds.append(newId); cells[seed.key] = sc
    }
    let canF = canExtend(newGrad, dir: "forward", gridW: gridW, gridH: gridH, cells: cells, mode: dev.cbMode, cfg: dev)
    let canB = canExtend(newGrad, dir: "backward", gridW: gridW, gridH: gridH, cells: cells, mode: dev.cbMode, cfg: dev)
    if !canF && !canB {
        if var sc = cells[seed.key] {
            sc.gradIds.removeAll { $0 == newId }
            cells[seed.key] = sc
        }
        return nil
    }
    gradients[newId] = newGrad
    return newGrad
}

// ─── main growth loop ───────────────────────────────────────────────

private func tryGrow(level: Int, cfg: LevelConfig, dev: GenConfig) -> Puzzle? {
    let gridW = 20, gridH = 20
    let targetN = dev.gradientCountOverride ?? defaultGradientCount(level)
    let (minLen, maxLen) = wordLenFor(level)
    // Levels 4-6 are the 2-gradient tier. With the default endpoint
    // bias of 0.5, branches almost always sprout from an endpoint of
    // the first gradient → L-shape every time. Lowering the bias to
    // ~0.05 makes interior cells equally likely branch points so the
    // output mix includes T-shapes and +-crosses, not just L-shapes.
    var dev = dev
    if level >= 4 && level <= 6 && dev.endpointCenterBias > 0.05 {
        dev.endpointCenterBias = 0.05
    }

    let bias = dev.huePrimaryBias ?? levelHuePrimaryBias(level)
    let assign = pickChannelsAndRoles(count: cfg.channelCount,
                                      huePrimaryBias: bias)

    var cells: [String: GrowCell] = [:]
    var gradients: [Int: GrowGrad] = [:]
    var nextId = 0

    let seedR = gridH / 2 + Util.randInt(-1, 1)
    let seedC = gridW / 2 + Util.randInt(-1, 1)
    let seedColor = pickSeedColor(cfg: dev)
    let seedDir: Direction = Util.chance(0.5) ? .h : .v
    let seedStep = pickStepDeltas(assign, cfg.ranges)
    let seedGrad = GrowGrad(id: nextId, dir: seedDir,
                            originR: seedR, originC: seedC,
                            dL: seedStep[.L] ?? 0,
                            dC: seedStep[.c] ?? 0,
                            dH: seedStep[.h] ?? 0,
                            seed: seedColor)
    gradients[nextId] = seedGrad
    cells["\(seedR),\(seedC)"] = GrowCell(color: seedColor, gradIds: [nextId])
    nextId += 1

    for _ in 0..<500 {
        let growing = gradients.values.filter { $0.status == "growing" }
        if growing.isEmpty {
            if gradients.count >= targetN { break }
            return nil
        }
        if let atCap = growing.first(where: { $0.length >= maxLen }) {
            atCap.status = "closed"
            continue
        }

        let belowMin = growing.filter { $0.length < minLen }
        let needsMore = gradients.count < targetN
        let branchProb = needsMore
            ? dev.branchRate * max(0, 1 - Double(gradients.count) / (Double(targetN) * 1.2))
            : 0
        let preferBelowMin = !belowMin.isEmpty && Util.chance(0.75)

        var branched = false
        if !preferBelowMin && Util.chance(branchProb) {
            if tryBranch(cells: &cells, gradients: &gradients,
                         assign: assign, ranges: cfg.ranges,
                         dev: dev, gridW: gridW, gridH: gridH,
                         newId: nextId) != nil {
                nextId += 1
                branched = true
            }
        }
        if branched { continue }

        let pool = preferBelowMin ? belowMin : growing
        guard let g = Util.randomElement(pool) else { return nil }
        let canF = canExtend(g, dir: "forward", gridW: gridW, gridH: gridH, cells: cells, mode: dev.cbMode, cfg: dev)
        let canB = canExtend(g, dir: "backward", gridW: gridW, gridH: gridH, cells: cells, mode: dev.cbMode, cfg: dev)
        if !canF && !canB {
            if g.length >= minLen { g.status = "closed"; continue }
            return nil
        }
        let dir: String = (canF && canB) ? (Util.chance(0.5) ? "forward" : "backward")
                                         : (canF ? "forward" : "backward")
        commitExtend(g, dir: dir, cells: &cells)

        if g.length >= minLen {
            let closedLens = Set(gradients.values
                .filter { $0.status == "closed" }
                .map { $0.length })
            let diversityActive = dev.lengthDiversityBias > 0
            let diversityMult = diversityActive
                ? (closedLens.contains(g.length)
                   ? 1 - dev.lengthDiversityBias * 0.5
                   : 1 + dev.lengthDiversityBias * 0.5)
                : 1.0
            let closeRate = dev.closeRate * diversityMult
            if Util.chance(closeRate) { g.status = "closed" }
        }
    }

    for g in gradients.values {
        if g.status == "growing" {
            if g.length >= minLen { g.status = "closed" }
            else { return nil }
        }
    }
    if gradients.count < targetN { return nil }

    return finalize(cells: cells, gradients: gradients,
                    level: level, cfg: cfg, assign: assign,
                    mode: dev.cbMode)
}

// ─── finalize: trim + assemble output ───────────────────────────────

private func finalize(cells: [String: GrowCell],
                      gradients: [Int: GrowGrad],
                      level: Int, cfg: LevelConfig,
                      assign: ChannelAssignment,
                      mode: CBMode) -> Puzzle? {
    var minR = Int.max, maxR = Int.min, minC = Int.max, maxC = Int.min
    for key in cells.keys {
        let parts = key.split(separator: ",").map { Int($0)! }
        let r = parts[0], c = parts[1]
        minR = min(minR, r); maxR = max(maxR, r)
        minC = min(minC, c); maxC = max(maxC, c)
    }
    let gridW = maxC - minC + 1
    let gridH = maxR - minR + 1
    if gridW > 17 || gridH > 17 { return nil }

    // Intersections are NO LONGER auto-locked here — guard 3 below
    // decides per-intersection whether to lock the intersection
    // itself OR a neighboring arm cell. The distinction:
    //   - Same-length arms meeting at the intersection → swap-
    //     ambiguous. An arm-adjacent lock breaks the swap AND the
    //     player can deduce the intersection's color from linearity,
    //     so the intersection lock becomes redundant (revealing one
    //     more cell than needed for uniqueness).
    //   - Otherwise → the intersection lock is the minimum
    //     disambiguator.
    // Endpoint anchors (optional, tier-1 config only) are applied as
    // usual.
    var lockedSet: Set<String> = []
    if cfg.anchorEndpoints >= 1 {
        for g in gradients.values {
            let (r, c) = g.cellOf(g.minPos)
            lockedSet.insert("\(r - minR),\(c - minC)")
        }
    }

    // Flatten to PuzzleGradient with local coords.
    var outGrads: [PuzzleGradient] = []
    for g in gradients.values {
        let len = g.length
        var colors: [OKLCh] = []
        var specs: [GradientCellSpec] = []
        for i in 0..<len {
            let pos = g.minPos + i
            let (wr, wc) = g.cellOf(pos)
            let rr = wr - minR, cc = wc - minC
            let color = g.colors[pos]!
            colors.append(color)
            let key = "\(rr),\(cc)"
            let worldKey = "\(wr),\(wc)"
            let isIntersection = (cells[worldKey]?.gradIds.count ?? 0) >= 2
            specs.append(GradientCellSpec(
                r: rr, c: cc, pos: i, color: color,
                locked: lockedSet.contains(key),
                isIntersection: isIntersection))
        }
        outGrads.append(PuzzleGradient(
            id: g.id, dir: g.dir, len: len,
            cells: specs, colors: colors))
    }

    // Uniqueness guard 3 + minimum-lock intersection policy. For each
    // intersection (a cell shared by ≥ 2 gradients):
    //
    //   - If any 2 arms meeting at the intersection have the same
    //     cell count → swap-ambiguous. Lock the cell adjacent to the
    //     intersection on every arm beyond the first in that length
    //     group. Leave the intersection UNLOCKED — the arm lock
    //     breaks the swap AND lets the player deduce the intersection
    //     color from linearity (it's the only bank-member that
    //     extends the locked arm pair into a linear progression).
    //     Locking the intersection on top would reveal one more cell
    //     than the uniqueness argument requires.
    //
    //   - Otherwise → lock the intersection itself. No swap is
    //     possible (arm lengths differ), and the intersection lock
    //     kills within-gradient reversal by pinning the shared color.
    //
    // Guard 4 still runs below; its orientation-mask enumerator
    // double-checks reversal via intersection-consistency and adds
    // extra locks if anything slips through.
    struct Arm { let gi: Int; let intersectPos: Int; let cellIdx: [Int] }

    /// Helper: mark the intersection cell as locked in every gradient
    /// covering it, and add to `lockedSet`.
    func lockIntersection(memberships: [(gi: Int, pos: Int)]) {
        guard let first = memberships.first else { return }
        let g0 = outGrads[first.gi]
        guard let spec = g0.cells.first(where: { $0.pos == first.pos })
        else { return }
        lockedSet.insert("\(spec.r),\(spec.c)")
        for m in memberships {
            var gMut = outGrads[m.gi]
            for (idx, s) in gMut.cells.enumerated()
            where s.r == spec.r && s.c == spec.c {
                var updated = s
                updated.locked = true
                gMut.cells[idx] = updated
            }
            outGrads[m.gi] = gMut
        }
    }

    var intersectionMap: [String: [(gi: Int, pos: Int)]] = [:]
    for (gi, g) in outGrads.enumerated() {
        for spec in g.cells {
            intersectionMap["\(spec.r),\(spec.c)", default: []].append((gi, spec.pos))
        }
    }
    for (_, memberships) in intersectionMap where memberships.count >= 2 {
        var arms: [Arm] = []
        for m in memberships {
            let g = outGrads[m.gi]
            let fwd = g.cells.indices.filter { g.cells[$0].pos > m.pos }
            let bwd = g.cells.indices.filter { g.cells[$0].pos < m.pos }
            if !fwd.isEmpty { arms.append(Arm(gi: m.gi, intersectPos: m.pos, cellIdx: fwd)) }
            if !bwd.isEmpty { arms.append(Arm(gi: m.gi, intersectPos: m.pos, cellIdx: bwd)) }
        }
        let lenGroups = Dictionary(grouping: arms) { $0.cellIdx.count }
        var addedArmLock = false
        for (_, sameLen) in lenGroups where sameLen.count >= 2 {
            let unlocked = sameLen.filter { arm in
                let g = outGrads[arm.gi]
                return !arm.cellIdx.contains { g.cells[$0].locked }
            }
            guard unlocked.count >= 2 else { continue }
            for arm in unlocked.dropFirst() {
                let g = outGrads[arm.gi]
                let sorted = arm.cellIdx.sorted {
                    abs(g.cells[$0].pos - arm.intersectPos)
                        < abs(g.cells[$1].pos - arm.intersectPos)
                }
                guard let lockIdx = sorted.first else { continue }
                var gMut = outGrads[arm.gi]
                var spec = gMut.cells[lockIdx]
                spec.locked = true
                gMut.cells[lockIdx] = spec
                outGrads[arm.gi] = gMut
                lockedSet.insert("\(spec.r),\(spec.c)")
                addedArmLock = true
            }
        }
        if !addedArmLock {
            // No same-length arm group → intersection lock is the
            // minimum disambiguator.
            lockIntersection(memberships: memberships)
        }
    }

    // Uniqueness guard 3.5: perceptually-palindromic gradients.
    // See `hasPalindromicGradient` for the rationale — lock-based
    // disambiguation can't save a gradient whose colors mirror
    // themselves, so reject and let the outer loop retry.
    if hasPalindromicGradient(outGrads, mode: mode) { return nil }

    // Feedback-driven rejection: if this candidate's shape
    // signature has been flagged by the player as a bad puzzle, let
    // the outer loop retry with a different layout. The ledger caps
    // at 50 entries and ages out FIFO, so one or two past dislikes
    // don't permanently constrain the generator.
    let sig = PuzzleShape.signature(of: outGrads)
    if LikedPuzzleStore.isShapeDisliked(sig) { return nil }

    // Guard 3.6 (L-shape rejection) was removed — it was vetoing
    // nearly every 2-gradient tier-2 puzzle (levels 4-6) because the
    // config there has `anchorEndpoints: 0`, so almost all locks are
    // intersections by construction. The vetoes starved the
    // generator and caused the "infinite building" symptom. Guard 4
    // (orientation-mask enumerator below) is the correct place to
    // catch genuine L-shape ambiguity; if L-shapes still slip
    // through there, that's where to fix it, not here.

    // Uniqueness guard 4: orientation-mask enumerator.
    //
    // Each gradient can be read forward or reversed, giving 2^N
    // combinations across N gradients. Mask=0 (all original) is valid
    // by construction; any additional valid mask means the puzzle has
    // multiple solutions. For each mask check (a) every locked cell's
    // mask-implied color matches spec.color, and (b) every
    // intersection cell gets consistent colors from each covering
    // gradient. If >1 mask is valid, lock a non-palindromic cell in
    // an ambiguous gradient and re-enumerate. Supersedes the older
    // heuristic that force-locked pos-0 whenever a gradient's only
    // lock sat at its odd-length center — that rule was conservative
    // (fired on plenty of cases that intersection constraints already
    // disambiguated) and blind to the rare double-reversal case where
    // two ambiguous gradients' reversed colors happen to agree at a
    // shared intersection. N ≤ 10 via defaultGradientCount; cap at 16.
    if outGrads.count <= 16 {
        func palindromic(_ pos: Int, len: Int) -> Bool { pos == len - 1 - pos }
        func maskValid(_ mask: UInt64) -> Bool {
            var cellColors: [Int: OKLCh] = [:]
            for i in 0..<outGrads.count {
                let reversed = (mask >> i) & 1 == 1
                let g = outGrads[i]
                for spec in g.cells {
                    let intended = reversed ? g.colors[g.len - 1 - spec.pos] : g.colors[spec.pos]
                    if spec.locked, !OK.equal(intended, spec.color, mode: mode) {
                        return false
                    }
                    let key = spec.r * 32 + spec.c
                    if let existing = cellColors[key] {
                        if !OK.equal(existing, intended, mode: mode) { return false }
                    } else {
                        cellColors[key] = intended
                    }
                }
            }
            return true
        }
        func validMasks() -> [UInt64] {
            let n = outGrads.count
            var out: [UInt64] = []
            for m in 0..<(UInt64(1) << n) where maskValid(m) { out.append(m) }
            return out
        }
        // Each iteration locks at most one cell, and a gradient may
        // need multiple locks to collapse the ambiguous mask set —
        // especially when intersection constraints are weak. The old
        // `outGrads.count + 1` ceiling exited after one lock per
        // gradient, which allowed partially-disambiguated puzzles to
        // ship if the first lock hit a coincident color. Budget every
        // free cell plus a small margin; `didLock=false` still bails
        // early when no progress is possible.
        let totalCells = outGrads.reduce(0) { $0 + $1.len }
        let maxIters = totalCells + outGrads.count + 1
        var iter = 0
        while iter < maxIters {
            iter += 1
            let masks = validMasks()
            if masks.isEmpty { return nil }  // inconsistent state — bail
            if masks.count == 1 { break }
            // Greedy min-lock: pick the gradient whose "reversed" bit
            // appears in the most remaining valid masks. Locking a
            // non-palindromic cell in that gradient kills every mask
            // where its bit is set, collapsing the ambiguous set as
            // fast as possible. Ties broken by lower gi for stability.
            var chosenGi: Int? = nil
            var bestKill = 0
            for gi in 0..<outGrads.count {
                let bit = UInt64(1) << gi
                let oneCount = masks.reduce(into: 0) { $0 += ($1 & bit) != 0 ? 1 : 0 }
                if oneCount == 0 || oneCount == masks.count { continue }  // bit already fixed
                if oneCount > bestKill {
                    bestKill = oneCount
                    chosenGi = gi
                }
            }
            guard let gi = chosenGi else { break }
            let len = outGrads[gi].len
            var didLock = false
            for k in 0..<outGrads[gi].cells.count {
                let spec = outGrads[gi].cells[k]
                if spec.locked || palindromic(spec.pos, len: len) { continue }
                var g = outGrads[gi]
                g.cells[k].locked = true
                outGrads[gi] = g
                lockedSet.insert("\(spec.r),\(spec.c)")
                didLock = true
                break
            }
            if !didLock { return nil }
        }
        // Safety net: if the loop exhausted its iteration budget
        // without collapsing to a single valid mask, the puzzle is
        // still ambiguous — reject instead of shipping it.
        if validMasks().count > 1 { return nil }
    }

    // Build board grid with solution colors + locks.
    var board: [[BoardCell]] = Array(
        repeating: Array(repeating: .dead, count: gridW),
        count: gridH)
    for g in outGrads {
        for spec in g.cells {
            if board[spec.r][spec.c].kind == .dead {
                board[spec.r][spec.c] = BoardCell(
                    kind: .cell,
                    solution: spec.color,
                    placed: spec.locked ? spec.color : nil,
                    locked: spec.locked,
                    isIntersection: spec.isIntersection,
                    gradIds: [g.id])
            } else {
                var cell = board[spec.r][spec.c]
                cell.isIntersection = true
                if !cell.gradIds.contains(g.id) { cell.gradIds.append(g.id) }
                if spec.locked {
                    cell.locked = true
                    cell.placed = spec.color
                }
                board[spec.r][spec.c] = cell
            }
        }
    }

    // Every gradient must have at least one free (unlocked) cell.
    if !outGrads.allSatisfy({ g in g.cells.contains(where: { !$0.locked }) }) {
        return nil
    }

    var bank: [BankItem] = []
    var uid = 0
    var bankedCells: Set<Int> = []
    for g in outGrads {
        for spec in g.cells where !spec.locked {
            let key = spec.r * 32 + spec.c
            if bankedCells.contains(key) { continue }
            bankedCells.insert(key)
            bank.append(BankItem(id: uid, color: spec.color))
            uid += 1
        }
    }

    // Proximity metrics + low-level gate.
    let lineProx = minInterGradientLineDist(outGrads.map { $0.colors }, mode: mode)
    let pairProx = cellPairProximityScore(outGrads, mode: mode)
    let extrapProx = extrapolationProximityScore(outGrads, mode: mode)
    if let cap = pairProxCap(level), pairProx > cap { return nil }
    let difficulty = scoreDifficulty(
        gradients: outGrads,
        bankCount: bank.count,
        channelCount: cfg.channelCount,
        primary: assign.primary,
        pairProx: pairProx,
        extrapProx: extrapProx,
        mode: mode)
    // Difficulty band gating moved out of `finalize` and into
    // `generatePuzzle`. The outer loop now routes candidates by
    // their actual computed difficulty (accept == target, stash >
    // target, discard < target) so higher-difficulty results can be
    // preserved for future levels instead of being thrown away here.
    // `levelDifficultyBand` is kept in the file only for callers
    // that still want a coarse range.
    _ = difficulty  // silences the unused warning if difficulty isn't read below

    let shuffled = Util.shuffle(bank)
    return Puzzle(
        level: level, gridW: gridW, gridH: gridH,
        board: board,
        bank: shuffled.map { Optional($0) },
        initialBankCount: shuffled.count,
        gradients: outGrads,
        channelCount: cfg.channelCount,
        activeChannels: assign.active,
        primaryChannel: assign.primary,
        difficulty: difficulty,
        pairProx: pairProx,
        extrapProx: extrapProx,
        interDist: lineProx)
}

// ─── public entry ───────────────────────────────────────────────────

/// Ring buffer of the most recent puzzle fingerprints returned from
/// `generatePuzzle`. Uses position-aware fingerprints (not just
/// direction+length) so same-shape puzzles at different grid
/// positions are treated as distinct. Prevents the generator from
/// converging on the same layout several levels in a row.
private let recentShapesLock = NSLock()
private var recentShapes: [String] = []
private let recentShapeLimit = 16

private func pushRecentShape(_ sig: String) {
    recentShapesLock.lock()
    defer { recentShapesLock.unlock() }
    recentShapes.append(sig)
    if recentShapes.count > recentShapeLimit {
        recentShapes.removeFirst(recentShapes.count - recentShapeLimit)
    }
}

private func isRecentShape(_ sig: String) -> Bool {
    recentShapesLock.lock()
    defer { recentShapesLock.unlock() }
    return recentShapes.contains(sig)
}

/// Targeted-generation hook mirroring the web repo's `tryGrowOnce`.
/// Single grower attempt — returns nil on guard failure so the
/// targeted path can run its own retry budget instead of inheriting
/// `generatePuzzle`'s internal loop + fallback semantics.
func tryGrowOnce(level: Int, config: GenConfig = GenConfig()) -> Puzzle? {
    let cfg = applyConfig(levelConfig(level), config)
    return tryGrow(level: level, cfg: cfg, dev: config)
}

func generatePuzzle(level: Int, config: GenConfig = GenConfig()) -> Puzzle {
    let cfg = applyConfig(levelConfig(level), config)
    // Target difficulty maps 1:1 from the requested level, capped at
    // the 1-10 range scoreDifficulty returns. Early levels effectively
    // want difficulty == level; at level ≥ 10 the generator just
    // keeps aiming for the hardest tier.
    let target = min(10, max(1, level))

    // Below-target buckets are now stale — purge before anything else
    // so the ledger stays bounded and we don't accidentally pop an
    // easier puzzle back out.
    StashedPuzzleStore.purgeBelow(difficulty: target)

    // Helper: position—aware fingerprint for a puzzle.
    func fp(_ p: Puzzle) -> String {
        PuzzleShape.fingerprint(of: p.gradients, gridW: p.gridW, gridH: p.gridH)
    }

    // Cache hit first — a previous run may have produced a puzzle at
    // exactly this difficulty while aiming for an earlier level. Pay
    // the decode cost instead of the full regeneration. Skip the pop
    // when the cached fingerprint matches a recently-used or already-
    // solved puzzle.
    if let cachedJSON = StashedPuzzleStore.pop(difficulty: target),
       let data = cachedJSON.data(using: .utf8),
       let doc = try? CreatorCodec.decode(data),
       let puzzle = CreatorCodec.rebuild(doc, level: level) {
        let f = fp(puzzle)
        if !isRecentShape(f), !SolvedPuzzleHistory.contains(f) {
            pushRecentShape(f)
            return puzzle
        }
        // Fall through to generation if this cache entry would
        // duplicate a recent or already-solved puzzle.
    }

    // Last generated candidate regardless of difficulty — kept around
    // as the absolute-last-resort return value so the generator never
    // falls through to a hardcoded layout.
    var lastSeen: Puzzle? = nil

    /// Helper: generate a candidate, route it according to difficulty
    /// vs. the desired window, and return true when we should return
    /// it to the caller. `dedupRecent = true` additionally rejects
    /// candidates whose fingerprint matches a recently-returned or
    /// previously-solved puzzle — set during strict + soft phases to
    /// keep output varied; dropped in the emergency loop so we can't
    /// spin forever on a tight level config.
    func routeCandidate(_ candidate: Puzzle,
                         acceptWindow: ClosedRange<Int>,
                         dedupRecent: Bool) -> Bool {
        lastSeen = candidate
        let f = fp(candidate)
        if acceptWindow.contains(candidate.difficulty) {
            if dedupRecent {
                if isRecentShape(f) { return false }
                if SolvedPuzzleHistory.contains(f) { return false }
            }
            pushRecentShape(f)
            return true
        }
        // Anything harder than the top of the accept window gets
        // stashed at its actual difficulty so a later, harder level
        // can pop it. Anything easier is discarded — retrying is a
        // better bet than shipping a too-easy puzzle now.
        if candidate.difficulty > acceptWindow.upperBound {
            if let json = try? CreatorCodec.encodePuzzle(candidate) {
                StashedPuzzleStore.stash(
                    puzzleJSON: json,
                    difficulty: candidate.difficulty
                )
            }
        }
        return false
    }

    // Strict phase: accept only difficulty == target. Most puzzles
    // should land here; over-shooting generator output builds up the
    // higher-difficulty stash for future levels. Recent-fingerprint
    // dedup + solved-history check are on so the player never sees
    // the same layout twice.
    for _ in 0..<500 {
        if let candidate = tryGrow(level: level, cfg: cfg, dev: config),
           routeCandidate(candidate, acceptWindow: target...target,
                          dedupRecent: true) {
            return candidate
        }
    }

    // Soft gate: widen UPWARD only — accept target through target+2.
    // Never accept easier than target; that's the failure mode the
    // "no fallback" rule was trying to prevent in the first place.
    // Stash any overshoot beyond the ceiling as usual.
    let softHigh = min(10, target + 2)
    for _ in 0..<500 {
        if let candidate = tryGrow(level: level, cfg: cfg, dev: config),
           routeCandidate(candidate, acceptWindow: target...softHigh,
                          dedupRecent: true) {
            return candidate
        }
    }

    // Stash fallback: pull a harder puzzle out of the cache rather
    // than shipping a bad difficulty. Prefer closest-to-target first.
    // Still honour dedup at this tier — if the only stashed candidate
    // matches a recent or solved fingerprint, fall through to the
    // emergency loop.
    for d in target...min(10, target + 3) {
        if let cachedJSON = StashedPuzzleStore.pop(difficulty: d),
           let data = cachedJSON.data(using: .utf8),
           let doc = try? CreatorCodec.decode(data),
           let puzzle = CreatorCodec.rebuild(doc, level: level) {
            let f = fp(puzzle)
            if !isRecentShape(f), !SolvedPuzzleHistory.contains(f) {
                pushRecentShape(f)
                return puzzle
            }
        }
    }

    // Relaxed phase: prefer `>= target`, 500 additional attempts.
    // Dedup is off here — at this point we've already paid 1000
    // strict+soft rejections; variety gives way to shipping
    // SOMETHING. Track the highest-difficulty easier candidate too
    // in case even this phase doesn't cross target.
    var bestSeen: Puzzle? = nil
    for _ in 0..<500 {
        guard let candidate = tryGrow(level: level, cfg: cfg, dev: config)
        else { continue }
        if candidate.difficulty >= target {
            pushRecentShape(fp(candidate))
            return candidate
        }
        if bestSeen == nil || candidate.difficulty > (bestSeen?.difficulty ?? 0) {
            bestSeen = candidate
        }
    }

    // Last-ditch: the best easier candidate we saw. Not ideal — the
    // player will get a level that's below target difficulty — but
    // it's a real generator output rather than a canned layout, and
    // it saves the app from an infinite build spinner. A level whose
    // `LevelConfig` genuinely can't produce `target` difficulty has
    // to terminate somewhere; this is that somewhere.
    if let best = bestSeen {
        pushRecentShape(fp(best))
        return best
    }

    // tryGrow has returned nil 5500+ times in a row — extreme config
    // failure. Keep trying (no difficulty floor) so the caller still
    // gets a puzzle instead of a hang.
    while true {
        if let p = tryGrow(level: level, cfg: cfg, dev: config) {
            pushRecentShape(fp(p))
            return p
        }
    }
}

// Handcrafted fallback removed: `generatePuzzle` never returns a
// canned layout anymore. If the strict / soft / stash phases can't
// produce a match, the loop keeps calling `tryGrow` until it does.
// Leaving the function absent instead of stubbed so nothing calls
// into a hardcoded "default" puzzle by accident.
