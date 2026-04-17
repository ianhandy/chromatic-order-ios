//  Cellular growth puzzle generator. Swift port of src/generate.js.
//
//  One seed cell + one seed color grows into a whole puzzle via
//  per-tick weighted decisions (branch vs extend vs close). All color
//  math is OKLCh / OKLab — distances are perceptual ΔE, so "these
//  cells look similar" matches the eye regardless of hue / L region.

import Foundation

// ─── config / tuning knobs ──────────────────────────────────────────

struct GenConfig {
    var huePrimaryBias: Double = 0.75
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
        L: lMid + Double.random(in: 0..<lSpan),
        c: cMid + Double.random(in: 0..<cSpan),
        h: Double.random(in: 0..<360)
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
    var pick = Double.random(in: 0..<total)
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
    if Util.chance(dev.symmetryRate), let src = sameDir.randomElement() {
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

    let assign = pickChannelsAndRoles(count: cfg.channelCount,
                                      huePrimaryBias: dev.huePrimaryBias)

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
        guard let g = pool.randomElement() else { return nil }
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

    // Intersections and optional endpoint anchors are pre-locked.
    var lockedSet: Set<String> = []
    for (key, cell) in cells where cell.gradIds.count >= 2 {
        let parts = key.split(separator: ",").map { Int($0)! }
        lockedSet.insert("\(parts[0] - minR),\(parts[1] - minC)")
    }
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

    // Uniqueness guard 1: odd-length gradient whose only lock sits at
    // the exact center has two valid orderings; lock pos-0 too.
    for gi in 0..<outGrads.count {
        var g = outGrads[gi]
        let center = g.len % 2 == 1 ? (g.len - 1) / 2 : -1
        let hasAnchoringLock = g.cells.contains(where: { $0.locked && $0.pos != center })
        if hasAnchoringLock { continue }
        var endpoint = g.cells[0]
        if !endpoint.locked {
            endpoint.locked = true
            g.cells[0] = endpoint
            lockedSet.insert("\(endpoint.r),\(endpoint.c)")
        }
        outGrads[gi] = g
    }

    // Uniqueness guard 2: scan every pair of free cells and lock one
    // of any pair that's too close in color. canExtend rejects pairs
    // below ΔE 2 (OK.equal); anything just past that — distinct to
    // the math, indistinguishable to the solver — still makes
    // playtesters flag the puzzle as "multiple solutions." Tighter
    // threshold (ΔE 4) for the free-cell pool specifically, since
    // these are the cells the player has to disambiguate.
    let ambiguityThreshold: Double = 4.0
    var freePositions: [(r: Int, c: Int, color: OKLCh, gid: Int)] = []
    var seenPositions: Set<String> = []
    for g in outGrads {
        for spec in g.cells where !spec.locked {
            let key = "\(spec.r),\(spec.c)"
            if seenPositions.insert(key).inserted {
                freePositions.append((spec.r, spec.c, spec.color, g.id))
            }
        }
    }
    // One lock per pass; repeat until no conflicts remain (bounded by
    // the number of free cells so can't infinite-loop).
    var guardPasses = 0
    while guardPasses < freePositions.count {
        guardPasses += 1
        var flagged: (r: Int, c: Int)? = nil
        outer: for i in 0..<freePositions.count {
            for j in (i + 1)..<freePositions.count {
                if OK.dist(freePositions[i].color, freePositions[j].color, mode: mode) < ambiguityThreshold {
                    flagged = (freePositions[i].r, freePositions[i].c)
                    break outer
                }
            }
        }
        guard let f = flagged else { break }
        lockedSet.insert("\(f.r),\(f.c)")
        for gi in 0..<outGrads.count {
            var g = outGrads[gi]
            var dirty = false
            for k in 0..<g.cells.count where g.cells[k].r == f.r && g.cells[k].c == f.c {
                if !g.cells[k].locked { g.cells[k].locked = true; dirty = true }
            }
            if dirty { outGrads[gi] = g }
        }
        freePositions.removeAll { $0.r == f.r && $0.c == f.c }
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
    for g in outGrads {
        for spec in g.cells where !spec.locked {
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

    let shuffled = bank.shuffled()
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

func generatePuzzle(level: Int, config: GenConfig = GenConfig()) -> Puzzle {
    let cfg = applyConfig(levelConfig(level), config)
    for _ in 0..<500 {
        if let puz = tryGrow(level: level, cfg: cfg, dev: config) {
            return puz
        }
    }
    return makeFallback(level: level)
}

// Handcrafted fallback for the rare case the grower can't find a layout
// within 500 attempts. Three real OKLCh gradients.
private func makeFallback(level: Int) -> Puzzle {
    let gridW = 6, gridH = 5
    func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    let h0: [OKLCh] = (0..<4).map { OKLCh(L: 0.60, c: 0.15, h: OK.normH(40 + Double($0) * 30)) }
    let h1: [OKLCh] = (0..<4).map { OKLCh(L: 0.45, c: 0.14, h: OK.normH(200 - Double($0) * 25)) }
    let vc: [OKLCh] = (0..<3).map {
        OKLCh(L: lerp(0.60, 0.45, Double($0) / 2.0),
              c: lerp(0.15, 0.14, Double($0) / 2.0),
              h: OK.normH(100 + Double($0) * 37.5))
    }
    func specs(dir: Direction, row: Int, col: Int, colors: [OKLCh], lockAt: Set<Int>) -> [GradientCellSpec] {
        colors.enumerated().map { (i, color) in
            let r = dir == .h ? row : row + i
            let c = dir == .h ? col + i : col
            return GradientCellSpec(r: r, c: c, pos: i, color: color,
                                     locked: lockAt.contains(i),
                                     isIntersection: lockAt.contains(i))
        }
    }
    let g0 = PuzzleGradient(id: 0, dir: .h, len: 4,
                            cells: specs(dir: .h, row: 1, col: 0, colors: h0, lockAt: [2]),
                            colors: h0)
    let g1 = PuzzleGradient(id: 1, dir: .h, len: 4,
                            cells: specs(dir: .h, row: 3, col: 1, colors: h1, lockAt: [1]),
                            colors: h1)
    let g2 = PuzzleGradient(id: 2, dir: .v, len: 3,
                            cells: specs(dir: .v, row: 1, col: 2, colors: vc, lockAt: [0, 2]),
                            colors: vc)
    var board: [[BoardCell]] = Array(
        repeating: Array(repeating: .dead, count: gridW), count: gridH)
    for g in [g0, g1, g2] {
        for spec in g.cells {
            if board[spec.r][spec.c].kind == .dead {
                board[spec.r][spec.c] = BoardCell(
                    kind: .cell, solution: spec.color,
                    placed: spec.locked ? spec.color : nil,
                    locked: spec.locked,
                    isIntersection: spec.isIntersection,
                    gradIds: [g.id])
            } else {
                var cell = board[spec.r][spec.c]
                cell.isIntersection = true
                cell.gradIds.append(g.id)
                if spec.locked { cell.locked = true; cell.placed = spec.color }
                board[spec.r][spec.c] = cell
            }
        }
    }
    var bank: [BankItem] = []
    var uid = 0
    for g in [g0, g1, g2] {
        for spec in g.cells where !spec.locked {
            bank.append(BankItem(id: uid, color: spec.color))
            uid += 1
        }
    }
    let shuffled = bank.shuffled()
    return Puzzle(
        level: level, gridW: gridW, gridH: gridH,
        board: board, bank: shuffled.map { Optional($0) },
        initialBankCount: shuffled.count,
        gradients: [g0, g1, g2],
        channelCount: 1,
        activeChannels: [.h],
        primaryChannel: .h,
        difficulty: 2, pairProx: 0, extrapProx: 0, interDist: 50)
}
