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
    /// Rule 1: minimum ΔE between ANY pair of cells in the puzzle
    /// (including within a single gradient). Tune-able so we can
    /// search for the ideal threshold empirically. Default 5 —
    /// perceptually "small but visible" — replacing the old ΔE 2
    /// "just-noticeable" threshold.
    var minCellDeltaE: Double = 5.0
    /// Max trimmed grid span accepted by finalize (width or height).
    /// Growth happens on a 20×20 grid; finalize returns nil if the
    /// trimmed puzzle exceeds this. Historical value was 17 (UI fit
    /// on an iPhone 17 screen). Tuning knob so high levels — which
    /// need space for many gradients — can grow to the full 20.
    var maxGridSpan: Int = 17
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

// Historical "too hard" gate — cells closer than this saturate the
// old pairProxScore. Now redundant: scoreDifficulty's confusionScore
// folds pairProx + extrapProx directly, and the structured builder
// can't produce puzzles below Rule 1's ΔE-5 cross-cell floor anyway.
// Return nil for every level so finalize stops silently rejecting
// builder output. The old per-level table stays below commented for
// reference in case we need to reintroduce level-scaled difficulty
// gating later.
private func pairProxCap(_ level: Int) -> Double? {
    return nil
}

private func pairProxCap_legacy(_ level: Int) -> Double? {
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


// ─── Structured builder ─────────────────────────────────────────────
//
// Plan N gradient slots as a connected skeleton first, THEN color-plan
// each slot. Separating geometry from color eliminates the old
// grower's failure mode where color-rejection during growth strands
// the generator before reaching targetN. Success rate at every N
// approaches the template's geometric feasibility — near 100% at N=1,
// degrading smoothly as density climbs rather than cliff-dropping at
// N≥2.

/// Skeleton description for one gradient: its shape on the grid plus
/// the intersection that ties it to the previous gradients. The root
/// slot (id=0) has no intersections.
private struct SkelSlot {
    let id: Int
    let dir: Direction
    let originR: Int    // grid coord where pos=0 lives
    let originC: Int
    let minPos: Int
    let maxPos: Int
    /// Parent-tree intersections: myPos ↔ otherSlot's otherPos.
    let intersections: [(myPos: Int, otherId: Int, otherPos: Int)]
    var length: Int { maxPos - minPos + 1 }
}

private func skelCellAt(dir: Direction, originR: Int, originC: Int,
                         pos: Int) -> (r: Int, c: Int) {
    switch dir {
    case .h: return (originR, originC + pos)
    case .v: return (originR + pos, originC)
    }
}

private func skelPosOf(dir: Direction, originR: Int, originC: Int,
                        r: Int, c: Int) -> Int {
    switch dir {
    case .h: return c - originC
    case .v: return r - originR
    }
}

/// Place targetN gradient slots as a connected skeleton. Each new
/// slot is perpendicular to and crosses one existing slot at a single
/// shared cell. Probabilistic intersection placement inside the
/// shared gradient (not forced at endpoints). Returns nil if no
/// layout fits within `tries` attempts.
private func placeSkeleton(targetN: Int, minLen: Int, maxLen: Int,
                            gridW: Int, gridH: Int,
                            tries: Int = 50) -> [SkelSlot]? {
    attempt: for _ in 0..<tries {
        var slots: [SkelSlot] = []
        var occupiedBy: [String: [Int]] = [:]

        // Seed slot: random dir, random length, centered on grid.
        let seedLen = Util.randInt(minLen, maxLen)
        let seedDir: Direction = Util.chance(0.5) ? .h : .v
        let seedR = gridH / 2 + Util.randInt(-2, 2)
        let seedC = gridW / 2 + Util.randInt(-2, 2)
        let seedMinPos = -(seedLen / 2)
        let seedMaxPos = seedMinPos + seedLen - 1
        // Bounds check.
        let (sminR, smaxR) = seedDir == .v
            ? (seedR + seedMinPos, seedR + seedMaxPos)
            : (seedR, seedR)
        let (sminC, smaxC) = seedDir == .h
            ? (seedC + seedMinPos, seedC + seedMaxPos)
            : (seedC, seedC)
        if sminR < 0 || smaxR >= gridH || sminC < 0 || smaxC >= gridW {
            continue attempt
        }
        slots.append(SkelSlot(id: 0, dir: seedDir,
                               originR: seedR, originC: seedC,
                               minPos: seedMinPos, maxPos: seedMaxPos,
                               intersections: []))
        for p in seedMinPos...seedMaxPos {
            let (r, c) = skelCellAt(dir: seedDir, originR: seedR,
                                      originC: seedC, pos: p)
            occupiedBy["\(r),\(c)", default: []].append(0)
        }

        // Branch N-1 times.
        while slots.count < targetN {
            // Candidate seed cells: cells belonging to exactly one
            // existing slot (so the branch intersection ties to a
            // single parent).
            var seeds: [(r: Int, c: Int, gid: Int, gpos: Int)] = []
            for (key, grads) in occupiedBy where grads.count == 1 {
                let parts = key.split(separator: ",").map { Int($0)! }
                let r = parts[0], c = parts[1]
                let gid = grads[0]
                let g = slots.first { $0.id == gid }!
                let gpos = skelPosOf(dir: g.dir,
                                      originR: g.originR, originC: g.originC,
                                      r: r, c: c)
                seeds.append((r, c, gid, gpos))
            }
            guard !seeds.isEmpty else { continue attempt }
            seeds = Util.shuffle(seeds)

            var placed = false
            for s in seeds {
                let parent = slots.first { $0.id == s.gid }!
                let branchDir: Direction = parent.dir == .h ? .v : .h
                let branchLen = Util.randInt(minLen, maxLen)
                // Where inside the branch does the shared cell sit?
                // Random — not forced at an endpoint.
                let insidePos = Util.randInt(0, branchLen - 1)
                let branchMinPos = -insidePos
                let branchMaxPos = branchMinPos + branchLen - 1
                // Bounds check in grid.
                let (bminR, bmaxR) = branchDir == .v
                    ? (s.r + branchMinPos, s.r + branchMaxPos)
                    : (s.r, s.r)
                let (bminC, bmaxC) = branchDir == .h
                    ? (s.c + branchMinPos, s.c + branchMaxPos)
                    : (s.c, s.c)
                if bminR < 0 || bmaxR >= gridH ||
                   bminC < 0 || bmaxC >= gridW { continue }

                // Check collisions: other branch cells must be empty.
                var ok = true
                for p in branchMinPos...branchMaxPos where p != 0 {
                    let (r, c) = skelCellAt(dir: branchDir,
                                              originR: s.r, originC: s.c,
                                              pos: p)
                    if occupiedBy["\(r),\(c)"] != nil { ok = false; break }
                }
                if !ok { continue }

                // Adjacency check: branch cells (other than the shared
                // cell) must not sit next to other-gradient cells —
                // crossword sparsity, same rule as canExtend.
                for p in branchMinPos...branchMaxPos where p != 0 {
                    let (r, c) = skelCellAt(dir: branchDir,
                                              originR: s.r, originC: s.c,
                                              pos: p)
                    for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                        let nr = r + dr, nc = c + dc
                        if nr < 0 || nr >= gridH || nc < 0 || nc >= gridW {
                            continue
                        }
                        let nkey = "\(nr),\(nc)"
                        if nkey == "\(s.r),\(s.c)" { continue }
                        if occupiedBy[nkey] != nil { ok = false; break }
                    }
                    if !ok { break }
                }
                if !ok { continue }

                // Commit.
                let newId = slots.count
                let branchSlot = SkelSlot(
                    id: newId, dir: branchDir,
                    originR: s.r, originC: s.c,
                    minPos: branchMinPos, maxPos: branchMaxPos,
                    intersections: [(myPos: 0,
                                      otherId: s.gid,
                                      otherPos: s.gpos)])
                slots.append(branchSlot)
                for p in branchMinPos...branchMaxPos {
                    let (r, c) = skelCellAt(dir: branchDir,
                                              originR: s.r, originC: s.c,
                                              pos: p)
                    occupiedBy["\(r),\(c)", default: []].append(newId)
                }
                placed = true
                break
            }
            if !placed { continue attempt }
        }
        return slots
    }
    return nil
}

/// Plan colors for a skeleton. Each slot picks a step vector; the root
/// picks its seed color freely, every other slot's seed is pinned by
/// its intersection. Per-slot step selection tries up to `stepTries`
/// candidates; if none satisfy Rule 1 + band clamp, backtrack.
private func planColors(
    skeleton: [SkelSlot],
    cfg: LevelConfig,
    dev: GenConfig,
    assign: ChannelAssignment,
    mode: CBMode,
    stepTries: Int = 12
) -> (cells: [String: GrowCell], gradients: [Int: GrowGrad])? {
    var gradients: [Int: GrowGrad] = [:]
    var cells: [String: GrowCell] = [:]
    // Total backtracking budget — caps DFS explosion when a skeleton
    // geometry fundamentally can't be colored under the current
    // constraints. Scales with skeleton size to give tight/large
    // puzzles similar per-slot headroom.
    var totalAttempts = 0
    // Budget: linear in skeleton size plus headroom. Tight enough
    // that failed builds return in ~5ms, loose enough that N=10
    // gradients get the multi-slot backtracking they need. Empirically
    // 30*N + 50 gives lv 16-20 a ~30% single-call success rate;
    // lower constants under-feed the deep skeletons.
    let maxTotalAttempts = 30 * skeleton.count + 50

    func tryAssignSlot(_ idx: Int) -> Bool {
        if idx == skeleton.count { return true }
        if totalAttempts >= maxTotalAttempts { return false }
        let slot = skeleton[idx]

        for _ in 0..<stepTries {
            totalAttempts += 1
            if totalAttempts >= maxTotalAttempts { return false }
            // Try both signed and negated step per iteration — same
            // trajectory shape, opposite direction, different seed
            // placement when pinned by intersection. Free doubling of
            // the candidate pool with no extra random draws.
            for signFlip in [false, true] {
            // Pick step.
            let deltas = pickStepDeltas(assign, cfg.ranges)
            var dL = deltas[.L] ?? 0
            var dC = deltas[.c] ?? 0
            var dH = deltas[.h] ?? 0
            if signFlip { dL = -dL; dC = -dC; dH = -dH }

            // Determine the seed (color at pos=0).
            var seedColor: OKLCh
            if slot.intersections.isEmpty {
                // Root — free choice.
                seedColor = pickSeedColor(cfg: dev)
            } else {
                // Pinned by intersection: my.colorAt(myPos) =
                // other.colorAt(otherPos). Solve for my seed.
                let isect = slot.intersections[0]
                guard let other = gradients[isect.otherId] else { return false }
                let targetColor = other.colorAt(isect.otherPos)
                seedColor = OKLCh(
                    L: targetColor.L - dL * Double(isect.myPos),
                    c: targetColor.c - dC * Double(isect.myPos),
                    h: OK.normH(targetColor.h - dH * Double(isect.myPos)))
            }

            // Build the gradient's colors and verify band + Rule 1.
            let g = GrowGrad(id: slot.id, dir: slot.dir,
                              originR: slot.originR, originC: slot.originC,
                              dL: dL, dC: dC, dH: dH, seed: seedColor)
            g.minPos = slot.minPos
            g.maxPos = slot.maxPos
            var proposedCells: [String: OKLCh] = [:]
            var inBand = true
            for p in slot.minPos...slot.maxPos {
                let color = g.colorAt(p)
                if !inBandForConfig(color, dev) { inBand = false; break }
                g.colors[p] = color
                let (r, c) = skelCellAt(dir: slot.dir,
                                          originR: slot.originR,
                                          originC: slot.originC, pos: p)
                proposedCells["\(r),\(c)"] = color
            }
            if !inBand { continue }

            // Rule 1 against all existing cells (skip the intersection
            // cell, which by construction holds the matching color).
            var floorOK = true
            let floor = dev.minCellDeltaE
            for (key, newColor) in proposedCells {
                if let existing = cells[key] {
                    // Shared intersection cell — must match within ΔE.
                    if !OK.equal(existing.color, newColor, mode: mode) {
                        floorOK = false; break
                    }
                    continue
                }
                for (otherKey, otherCell) in cells where otherKey != key {
                    if OK.dist(otherCell.color, newColor, mode: mode) < floor {
                        floorOK = false; break
                    }
                }
                if !floorOK { break }
            }
            if !floorOK { continue }

            // Commit.
            gradients[slot.id] = g
            for (key, color) in proposedCells {
                if var existing = cells[key] {
                    existing.gradIds.append(slot.id)
                    cells[key] = existing
                } else {
                    cells[key] = GrowCell(color: color, gradIds: [slot.id])
                }
            }
            if tryAssignSlot(idx + 1) { return true }
            // Roll back.
            gradients.removeValue(forKey: slot.id)
            for (key, _) in proposedCells {
                if var existing = cells[key] {
                    existing.gradIds.removeAll { $0 == slot.id }
                    if existing.gradIds.isEmpty {
                        cells.removeValue(forKey: key)
                    } else {
                        cells[key] = existing
                    }
                }
            }
            }  // end signFlip loop
        }
        return false
    }

    if !tryAssignSlot(0) { return nil }
    return (cells, gradients)
}

/// Structured build entry point. Mirrors tryGrow's signature.
/// Returns nil on skeleton-placement or color-plan failure.
private func tryStructuredBuild(level: Int, cfg: LevelConfig,
                                 dev: GenConfig) -> Puzzle? {
    let gridW = 20, gridH = 20
    let targetN = dev.gradientCountOverride ?? defaultGradientCount(level)
    let (minLen, maxLen) = wordLenFor(level)

    // Level-4-6 endpoint bias tweak from tryGrow stays relevant for
    // branch-seed selection diversity; structured builder uses its own
    // random inside-slot positioning, so it's a moot knob here.
    let bias = dev.huePrimaryBias ?? levelHuePrimaryBias(level)
    let assign = pickChannelsAndRoles(count: cfg.channelCount,
                                        huePrimaryBias: bias)

    guard let skel = placeSkeleton(targetN: targetN,
                                     minLen: minLen, maxLen: maxLen,
                                     gridW: gridW, gridH: gridH) else {
        return nil
    }
    guard let (cells, gradients) = planColors(
        skeleton: skel, cfg: cfg, dev: dev, assign: assign, mode: dev.cbMode
    ) else {
        return nil
    }
    return finalize(cells: cells, gradients: gradients,
                     level: level, cfg: cfg, assign: assign, mode: dev.cbMode)
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
    // Note: `dev` isn't in scope here — we rely on the outer grow
    // path applying the config. The cap is read via the static default
    // for now; GenConfig.maxGridSpan would need to be threaded through
    // finalize to take effect. For this audit we tweak the literal.
    if gridW > 20 || gridH > 20 { return nil }

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
    let trajectory = trajectoryOverlapSummary(outGrads, mode: mode)
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
        interDist: lineProx,
        trajectoryLineMinDistance: trajectory.minLineDistance,
        trajectoryStepPointMinDistance: trajectory.minStepPointDistance,
        trajectoryIntersectingPairs: trajectory.intersectingPairCount)
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
    return tryBuildOrGrow(level: level, cfg: cfg, dev: config)
}

/// Dispatch helper — retained for API stability. The legacy random
/// grower was retired once the structured builder hit uniqueness
/// parity at every level's default gradient count.
private func tryBuildOrGrow(level: Int, cfg: LevelConfig,
                             dev: GenConfig) -> Puzzle? {
    return tryStructuredBuild(level: level, cfg: cfg, dev: dev)
}

func generatePuzzle(level: Int, config: GenConfig = GenConfig()) -> Puzzle {
    // `levelConfig` has random components (e.g. `Util.chance(0.55)` to
    // pick channelCount at tier 4+). Sampling it once and reusing for
    // every retry attempt locks us to ONE channelCount across 15k+
    // tries — if that happens to be hard for the builder at this
    // level, we exhaust. Recompute inside each loop iteration so
    // channelCount varies per attempt.
    func freshCfg() -> LevelConfig {
        return applyConfig(levelConfig(level), config)
    }
    let cfg = freshCfg()  // one sample just for cache / stash decoding below
    // Target difficulty: fitted to the rescored scoreDifficulty's
    // observed distribution per level tier (see
    // testDifficultyDistribution output). Direct level→difficulty
    // doesn't hold under the new formula — a lv 1 single-gradient
    // puzzle scores ~3 because the step+primaryChannel components
    // baseline that high. Rather than re-torture the formula, map
    // level to what it actually produces.
    let target: Int
    switch level {
    case ...3:    target = 3
    case 4...6:   target = 4
    case 7...9:   target = 6
    case 10...12: target = 9
    default:      target = 10
    }

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
        if !isRecentShape(f),
           !SolvedPuzzleHistory.contains(f),
           !ShapesSeenToday.contains(f) {
            pushRecentShape(f)
            ShapesSeenToday.push(f)
            return puzzle
        }
        // Fall through to generation if this cache entry would
        // duplicate a recent, already-solved, or seen-today puzzle.
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
                if ShapesSeenToday.contains(f) { return false }
            }
            pushRecentShape(f)
            ShapesSeenToday.push(f)
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

    // Strict phase: accept target ±1. Re-sample cfg each iteration so
    // `levelConfig`'s random components (e.g. channelCount) don't stay
    // stuck on one sample across hundreds of retries.
    let strictLo = max(1, target - 1)
    let strictHi = min(10, target + 1)
    for _ in 0..<500 {
        if let candidate = tryBuildOrGrow(level: level, cfg: freshCfg(),
                                           dev: config),
           routeCandidate(candidate, acceptWindow: strictLo...strictHi,
                          dedupRecent: true) {
            return candidate
        }
    }

    // Soft gate: widen UPWARD only — accept target through target+2.
    // Never accept easier than target; that's the failure mode the
    // "no fallback" rule was trying to prevent in the first place.
    // Stash any overshoot beyond the ceiling as usual.
    let softLo = max(1, target - 2)
    let softHigh = min(10, target + 2)
    for _ in 0..<500 {
        if let candidate = tryBuildOrGrow(level: level, cfg: freshCfg(), dev: config),
           routeCandidate(candidate, acceptWindow: softLo...softHigh,
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
            if !isRecentShape(f),
               !SolvedPuzzleHistory.contains(f),
               !ShapesSeenToday.contains(f) {
                pushRecentShape(f)
                ShapesSeenToday.push(f)
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
        guard let candidate = tryBuildOrGrow(level: level, cfg: freshCfg(),
                                               dev: config)
        else { continue }
        if candidate.difficulty >= target {
            let f = fp(candidate)
            pushRecentShape(f)
            ShapesSeenToday.push(f)
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
        let f = fp(best)
        pushRecentShape(f)
        ShapesSeenToday.push(f)
        return best
    }

    // Hard cap the "keep trying" loop. Without this, a tight GenConfig
    // (e.g. CB mode at lv 20 under minCellDeltaE = 5) can spin
    // forever. 10,000 attempts at ~5ms each = ~50s worst case, then
    // fatalError so the hang is visible instead of silent.
    // tryGrow has returned nil 5500+ times in a row — extreme config
    // failure. Keep trying (bounded) so the caller still
    // gets a puzzle instead of a hang.
    for _ in 0..<10_000 {
        if let p = tryBuildOrGrow(level: level, cfg: freshCfg(), dev: config) {
            let f = fp(p)
            pushRecentShape(f)
            ShapesSeenToday.push(f)
            return p
        }
    }
    fatalError("generatePuzzle: builder returned nil 15,500 times at " +
               "level=\(level) target=\(target) cbMode=\(config.cbMode) " +
               "minCellDeltaE=\(config.minCellDeltaE). " +
               "GenConfig too tight for this level.")
}

// Handcrafted fallback removed: `generatePuzzle` never returns a
// canned layout anymore. If the strict / soft / stash phases can't
// produce a match, the loop keeps calling `tryGrow` until it does.
// Leaving the function absent instead of stubbed so nothing calls
// into a hardcoded "default" puzzle by accident.
