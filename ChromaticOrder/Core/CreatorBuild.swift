//  Turns a CreatorState's laid gradients into a playable Puzzle and
//  derives the info the creator UI needs to show: difficulty score,
//  multiple-solutions warning, export JSON.

import Foundation

struct CreatorValidation {
    var gradientCount: Int
    var cellCount: Int
    var bankCount: Int
    var difficulty: Int
    /// Human-readable warnings that the creator UI surfaces. Empty
    /// string counts as "no issue."
    var warnings: [String]
    /// True iff the layout is ready to play — at least one gradient,
    /// enough clues, no structural problems. Non-structural warnings
    /// (e.g., "only 2 gradients") don't block play.
    var playable: Bool
}

enum CreatorBuilder {
    /// Build a playable Puzzle from the laid gradients. Intersections
    /// become locked clues; for any gradient whose only lock sits at
    /// the exact center of an odd-length line we also anchor pos 0 to
    /// remove the direction ambiguity — mirrors the web generator's
    /// uniqueness guard.
    /// @MainActor — reads CreatorState.gradients, which is isolated
    /// to the main actor.
    @MainActor
    static func build(from creator: CreatorState, level: Int = 1) -> (puzzle: Puzzle, validation: CreatorValidation)? {
        let laid = creator.gradients
        guard !laid.isEmpty else { return nil }

        // Bounding box — trim the canvas so the puzzle is tight.
        var minR = Int.max, maxR = Int.min, minC = Int.max, maxC = Int.min
        for g in laid {
            for idx in g.cells {
                minR = min(minR, idx.r); maxR = max(maxR, idx.r)
                minC = min(minC, idx.c); maxC = max(maxC, idx.c)
            }
        }
        let gridW = maxC - minC + 1
        let gridH = maxR - minR + 1

        // Flatten to per-cell owner list for intersection detection.
        var ownersByCell: [CellIndex: [Int]] = [:]
        for (gi, g) in laid.enumerated() {
            for idx in g.cells {
                ownersByCell[idx, default: []].append(gi)
            }
        }

        // Lock set. If the player has chosen specific cells to reveal
        // at start via manualLocks, those — and only those — count as
        // clues. Otherwise auto-lock the intersections (plus the
        // uniqueness-guard pass below) so fresh puzzles still work
        // without any manual tagging.
        var lockedSet: Set<CellIndex> = []
        let usingManual = !creator.manualLocks.isEmpty
        if usingManual {
            for world in creator.manualLocks {
                // Manual locks can only apply to cells that are
                // actually painted; ignore stale entries after undo.
                guard ownersByCell[world] != nil else { continue }
                lockedSet.insert(CellIndex(r: world.r - minR, c: world.c - minC))
            }
        } else {
            for (idx, owners) in ownersByCell where owners.count >= 2 {
                let local = CellIndex(r: idx.r - minR, c: idx.c - minC)
                lockedSet.insert(local)
            }
        }

        // Build puzzle gradients with per-cell specs in local coords.
        var outGrads: [PuzzleGradient] = []
        for (gi, g) in laid.enumerated() {
            var specs: [GradientCellSpec] = []
            for (pos, idx) in g.cells.enumerated() {
                let local = CellIndex(r: idx.r - minR, c: idx.c - minC)
                let isIntersection = (ownersByCell[idx]?.count ?? 0) >= 2
                specs.append(GradientCellSpec(
                    r: local.r, c: local.c, pos: pos,
                    color: g.colors[pos],
                    locked: lockedSet.contains(local),
                    isIntersection: isIntersection
                ))
            }
            outGrads.append(PuzzleGradient(
                id: gi, dir: g.dir, len: g.cells.count,
                cells: specs, colors: g.colors))
        }

        // Uniqueness guard — applies only when we're auto-locking
        // (no manual locks). When the player chose locks manually,
        // trust their choice — the warnings collected further down
        // will flag direction ambiguity if it sneaks through.
        if !usingManual {
            for gi in 0..<outGrads.count {
                var g = outGrads[gi]
                let center = g.len % 2 == 1 ? (g.len - 1) / 2 : -1
                let hasAnchoringLock = g.cells.contains(where: { $0.locked && $0.pos != center })
                if hasAnchoringLock { continue }
                var endpoint = g.cells[0]
                if !endpoint.locked {
                    endpoint.locked = true
                    g.cells[0] = endpoint
                    lockedSet.insert(CellIndex(r: endpoint.r, c: endpoint.c))
                }
                outGrads[gi] = g
            }
        }

        // Build the board grid (dead everywhere except the gradient cells).
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

        // Bank = every DISTINCT unlocked cell's solution color.
        // Intersections live in two gradients' cells[] arrays; without
        // the dedupe step they'd land in the bank twice — giving the
        // player a surplus swatch and making the "two free cells share
        // a color" check fire on the same cell vs itself.
        var bank: [BankItem] = []
        var seenBank: Set<CellIndex> = []
        var uid = 0
        for g in outGrads {
            for spec in g.cells where !spec.locked {
                let key = CellIndex(r: spec.r, c: spec.c)
                if seenBank.insert(key).inserted {
                    bank.append(BankItem(id: uid, color: spec.color)); uid += 1
                }
            }
        }
        bank.shuffle()

        // Channels present + primary — needed for difficulty scoring.
        let (channels, primary) = inferChannelsAndPrimary(from: outGrads)

        // Proximity metrics — reuse the live game's helpers.
        let pairProx = cellPairProximityScore(outGrads)
        let extrapProx = extrapolationProximityScore(outGrads)
        let lineProx = minInterGradientLineDist(outGrads.map { $0.colors })
        let difficulty = scoreDifficulty(
            gradients: outGrads,
            bankCount: bank.count,
            channelCount: channels.count,
            primary: primary,
            pairProx: pairProx,
            extrapProx: extrapProx)

        // Validation — collect warnings (most→least severe). Warnings
        // are surfaced in the creator UI; empty list means "ready."
        var warnings: [String] = []

        // 1. Zero clues at all — the player can't start solving.
        if lockedSet.isEmpty {
            warnings.append("No starter cells — tap a cell to reveal it at the start.")
        }

        // 2. Multiple solutions — two DISTINCT free cells share a
        // color (within perceptual ΔE). Dedupe by (r, c) so
        // intersections — present in two gradients' cells[] arrays —
        // don't match themselves and produce a false warning.
        var distinctFree: [(idx: CellIndex, color: OKLCh)] = []
        var seenFree: Set<CellIndex> = []
        for g in outGrads {
            for spec in g.cells where !spec.locked {
                let key = CellIndex(r: spec.r, c: spec.c)
                if seenFree.insert(key).inserted {
                    distinctFree.append((key, spec.color))
                }
            }
        }
        for i in 0..<distinctFree.count {
            var conflict = false
            for j in (i + 1)..<distinctFree.count {
                if OK.equal(distinctFree[i].color, distinctFree[j].color) {
                    warnings.append("Multiple solutions: two free cells share a color — lock one as a clue.")
                    conflict = true; break
                }
            }
            if conflict { break }
        }

        // 3. Direction ambiguity — a gradient with only one lock at
        // the exact center of an odd-length line has two valid
        // orderings. Auto-lock path handles this, but manual-lock
        // users can hit it.
        for g in outGrads {
            let center = g.len % 2 == 1 ? (g.len - 1) / 2 : -1
            let locks = g.cells.filter { $0.locked }
            if locks.count == 1, locks[0].pos == center {
                warnings.append("A gradient has only a center clue — either direction works. Lock a second cell.")
                break
            }
        }

        // 4. Fully-locked board — nothing to solve.
        if outGrads.allSatisfy({ g in g.cells.allSatisfy { $0.locked } }) {
            warnings.append("Every cell is locked — nothing for the player to solve.")
        }

        let puzzle = Puzzle(
            level: level,
            gridW: gridW, gridH: gridH,
            board: board,
            bank: bank.map { Optional($0) },
            initialBankCount: bank.count,
            gradients: outGrads,
            channelCount: channels.count,
            activeChannels: channels,
            primaryChannel: primary,
            difficulty: difficulty,
            pairProx: pairProx,
            extrapProx: extrapProx,
            interDist: lineProx)

        let validation = CreatorValidation(
            gradientCount: outGrads.count,
            cellCount: outGrads.reduce(0) { $0 + $1.len },
            bankCount: bank.count,
            difficulty: difficulty,
            warnings: warnings,
            playable: bank.count > 0 && !outGrads.isEmpty)

        return (puzzle, validation)
    }

    /// Which OKLCh channels actually vary across the laid gradients,
    /// and which of those dominates (largest average |step|). Used
    /// by scoreDifficulty.
    private static func inferChannelsAndPrimary(from gradients: [PuzzleGradient]) -> ([Channel], Channel) {
        var avgAbs: [Channel: Double] = [.L: 0, .c: 0, .h: 0]
        var n = 0
        for g in gradients where g.colors.count >= 2 {
            for i in 1..<g.colors.count {
                let a = g.colors[i - 1], b = g.colors[i]
                avgAbs[.L, default: 0] += abs(b.L - a.L)
                avgAbs[.c, default: 0] += abs(b.c - a.c)
                // Hue: wrap to [-180, 180] before taking magnitude.
                var dh = b.h - a.h
                if dh > 180 { dh -= 360 }
                if dh < -180 { dh += 360 }
                avgAbs[.h, default: 0] += abs(dh) / 180  // normalize to [0, 1]
                n += 1
            }
        }
        if n > 0 {
            for k in avgAbs.keys { avgAbs[k]! /= Double(n) }
        }
        // Channels whose average step isn't noise (>1e-4 in normalized
        // units) count as "active."
        let threshold = 1e-4
        let active = Channel.allCases.filter { (avgAbs[$0] ?? 0) > threshold }
        let sorted = active.sorted { (avgAbs[$0] ?? 0) > (avgAbs[$1] ?? 0) }
        let primary = sorted.first ?? .h
        // scoreDifficulty expects sorted-by-raw activeChannels; it
        // doesn't care about ordering, so we just hand it active.
        return (active.isEmpty ? [.h] : active, primary)
    }
}
