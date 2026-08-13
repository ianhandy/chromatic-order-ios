//  Generator integrity gates. Two classes of fault used to ship from
//  `finalize`, and both were invisible to the existing audits because
//  they only show up statistically:
//
//    1. Split lock flags on a shared cell. A crossing cell is stored
//       once PER GRADIENT, so the same board coordinate has two
//       `GradientCellSpec` copies. The uniqueness guards set `locked`
//       on one copy only, and the two downstream consumers then
//       disagree: the board OR-merges the flag (cell is pre-filled)
//       while the bank builder banks any position whose copy is
//       unlocked (swatch created for that same cell). The bank ends up
//       one item longer than the number of empty cells, the player can
//       never empty it, and the check button never enables. Board is
//       unwinnable except by skipping.
//
//    2. Cell pairs under `GenConfig.minCellDeltaE`. The floor is
//       supposed to hold between ANY two cells of the finished board.
//       `planColors` only compared a proposed gradient against the
//       already-committed cells, never against the rest of itself, so
//       a gradient's own cells (adjacent ones included) could land
//       closer than the floor.
//
//  Both gates below are statistical, so they need real sample counts.
//  Fault 1 sat at 4 boards in 1,680 (0.24%) before the fix, so a
//  10-board sample would have missed it far more often than not. Fault
//  2 was loud by comparison, 424 in 1,680 (25%), but concentrated
//  above level 10, so a levels-1-to-5 sample would have missed it too.

import XCTest


final class GeneratorIntegrityTests: XCTestCase {

    /// Boards per level. High enough that a sub-1% fault rate is caught
    /// with near certainty (80 x 21 = 1,680 boards per gate).
    private let boardsPerLevel = 80
    private let levels = Array(1...21)

    // MARK: helpers

    /// One board, generated with per-install state disabled. `deterministic`
    /// keeps the generator off the stash / seen-today / solved ledgers, so
    /// every sample is a fresh `finalize` output rather than a decoded
    /// cache entry, and the test leaves no residue in UserDefaults.
    private func makeBoard(level: Int, config: GenConfig) -> Puzzle {
        return generatePuzzle(level: level, config: config)
    }

    private func genConfig() -> GenConfig {
        var cfg = GenConfig()
        cfg.deterministic = true
        return cfg
    }

    /// Distinct board coordinates that carry a color, with their solution.
    /// Shared cells appear once (the board grid is already deduped).
    private func liveCells(_ p: Puzzle) -> [(r: Int, c: Int, color: OKLCh)] {
        var out: [(r: Int, c: Int, color: OKLCh)] = []
        for r in 0..<p.gridH {
            for c in 0..<p.gridW {
                let cell = p.board[r][c]
                guard cell.kind == .cell, let sol = cell.solution else { continue }
                out.append((r, c, sol))
            }
        }
        return out
    }

    /// Coordinates the bank builder would produce, reproduced from the
    /// gradient specs exactly the way `finalize` / `CreatorCodec.rebuild`
    /// do it: walk every gradient, bank each unlocked position once.
    private func bankedCoords(_ p: Puzzle) -> Set<Int> {
        var keys: Set<Int> = []
        for g in p.gradients {
            for spec in g.cells where !spec.locked {
                keys.insert(spec.r * 32 + spec.c)
            }
        }
        return keys
    }

    private func givenCoords(_ p: Puzzle) -> Set<Int> {
        var keys: Set<Int> = []
        for r in 0..<p.gridH {
            for c in 0..<p.gridW {
                let cell = p.board[r][c]
                if cell.kind == .cell, cell.locked { keys.insert(r * 32 + c) }
            }
        }
        return keys
    }

    /// Smallest ΔE between any two distinct cells of the board, under the
    /// config's CB mode (the same perception model the generator built
    /// the board in).
    private func minCellPairDistance(_ p: Puzzle, mode: CBMode) -> Double {
        let cells = liveCells(p)
        var best = Double.greatestFiniteMagnitude
        guard cells.count >= 2 else { return best }
        for i in 0..<(cells.count - 1) {
            for j in (i + 1)..<cells.count {
                let d = OK.dist(cells[i].color, cells[j].color, mode: mode)
                if d < best { best = d }
            }
        }
        return best
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        let idx = Int((Double(sorted.count - 1) * p).rounded(.down))
        return sorted[idx]
    }

    // MARK: gate 1, bank size matches the empty-cell count

    func testBankMatchesEmptyCellsAcrossLevels() {
        let cfg = genConfig()
        var faults = 0
        var boards = 0
        var report: [String] = []

        for level in levels {
            var levelFaults = 0
            for _ in 0..<boardsPerLevel {
                let p = makeBoard(level: level, config: cfg)
                boards += 1
                let bankCount = p.bank.compactMap { $0 }.count
                let empties = liveCells(p).filter { !p.board[$0.r][$0.c].locked }.count
                let overlap = bankedCoords(p).intersection(givenCoords(p))
                if bankCount != empties || !overlap.isEmpty {
                    levelFaults += 1
                    faults += 1
                    // First few faults get detail so a regression is
                    // diagnosable from the log alone.
                    if faults <= 5 {
                        report.append("lv \(level): bank=\(bankCount) empties=\(empties) " +
                                      "overlap=\(overlap.count) grid=\(p.gridW)x\(p.gridH)")
                    }
                }
                // Split lock flags are the mechanism behind the count
                // mismatch, so assert the invariant directly too: a
                // coordinate's given-ness must be single-valued.
                var flagsByCoord: [Int: Set<Bool>] = [:]
                for g in p.gradients {
                    for spec in g.cells {
                        flagsByCoord[spec.r * 32 + spec.c, default: []].insert(spec.locked)
                    }
                }
                for (key, flags) in flagsByCoord where flags.count > 1 {
                    if faults <= 10 {
                        report.append("lv \(level): split lock flag at " +
                                      "(\(key / 32),\(key % 32))")
                    }
                }
            }
            if levelFaults > 0 {
                report.append("lv \(level): \(levelFaults)/\(boardsPerLevel) faulty")
            }
        }

        print("[GeneratorIntegrity] bank/empty audit: \(faults)/\(boards) faulty boards")
        for line in report { print("[GeneratorIntegrity]   \(line)") }
        XCTAssertEqual(faults, 0,
                       "unwinnable boards: bank size does not match the empty-cell count")
    }

    // MARK: gate 2, the ΔE floor holds board-wide

    func testNoCellPairUnderConfiguredFloor() {
        let cfg = genConfig()
        let floor = GenConfig().minCellDeltaE
        var violations = 0
        var boards = 0
        var lines: [String] = []

        for level in levels {
            var minima: [Double] = []
            var levelViolations = 0
            for _ in 0..<boardsPerLevel {
                let p = makeBoard(level: level, config: cfg)
                boards += 1
                let m = minCellPairDistance(p, mode: cfg.cbMode)
                minima.append(m)
                if m < floor {
                    levelViolations += 1
                    violations += 1
                }
            }
            let worst = minima.min() ?? .nan
            lines.append(String(
                format: "lv %2d  min %.2f  p10 %.2f  median %.2f  under-floor %d/%d",
                level, worst, percentile(minima, 0.10),
                percentile(minima, 0.50), levelViolations, boardsPerLevel))
        }

        for line in lines { print("[GeneratorIntegrity] \(line)") }
        XCTAssertEqual(violations, 0,
                       "boards with a cell pair under ΔE \(floor): \(violations)/\(boards)")
    }

    // MARK: mechanism report, what actually binds the ΔE floor

    /// Classifies the CLOSEST cell pair on each board so a future
    /// regression tells us WHERE the floor leaks, not just that it did.
    /// Three buckets, because the fix only covers one of them and the
    /// distinction is the whole diagnosis:
    ///   - adjacent, same gradient: consecutive cells of one run, i.e.
    ///     the per-step ΔE. This is the bucket that was unguarded,
    ///     since `planColors` never compared a proposed gradient
    ///     against the rest of itself.
    ///   - non-adjacent, same gradient: a hue ramp wrapping around far
    ///     enough that two of its own distant cells meet again.
    ///   - cross gradient: two different runs, which `planColors` did
    ///     check against the committed cell dictionary all along.
    func testReportClosestPairMechanism() {
        let cfg = genConfig()
        let floor = GenConfig().minCellDeltaE
        var lines: [String] = []
        for level in [9, 10, 12, 15, 18, 21] {
            var adjacent = 0, sameGrad = 0, cross = 0
            var underFloor = 0
            var worst = Double.greatestFiniteMagnitude
            for _ in 0..<25 {
                let p = makeBoard(level: level, config: cfg)
                let cells = liveCells(p)
                var best = Double.greatestFiniteMagnitude
                var bestPair: (Int, Int) = (0, 0)
                for i in 0..<(cells.count - 1) {
                    for j in (i + 1)..<cells.count {
                        let d = OK.dist(cells[i].color, cells[j].color, mode: cfg.cbMode)
                        if d < best { best = d; bestPair = (i, j) }
                    }
                }
                worst = min(worst, best)
                if best < floor { underFloor += 1 }
                let a = cells[bestPair.0], b = cells[bestPair.1]
                var kind = "cross"
                for g in p.gradients {
                    let pa = g.cells.first { $0.r == a.r && $0.c == a.c }?.pos
                    let pb = g.cells.first { $0.r == b.r && $0.c == b.c }?.pos
                    if let pa, let pb {
                        kind = abs(pa - pb) == 1 ? "adjacent" : "sameGrad"
                        break
                    }
                }
                switch kind {
                case "adjacent": adjacent += 1
                case "sameGrad": sameGrad += 1
                default: cross += 1
                }
            }
            lines.append(String(
                format: "lv %2d  closest pair: adjacent %2d  sameGrad %2d  cross %2d" +
                        "   under-floor %2d/25  worst %.2f",
                level, adjacent, sameGrad, cross, underFloor, worst))
        }
        for line in lines { print("[GeneratorIntegrity] \(line)") }
    }

    // MARK: gate 3, the lock-normalisation helper itself

    func testNormalizeLockFlagsMakesGivennessSingleValued() {
        // Two gradients crossing at (1,1). The horizontal copy of the
        // shared cell is locked, the vertical copy is not, exactly the
        // state the uniqueness guards used to leave behind.
        let a = OKLCh(L: 0.50, c: 0.15, h: 10)
        let b = OKLCh(L: 0.55, c: 0.15, h: 40)
        let shared = OKLCh(L: 0.60, c: 0.15, h: 70)
        let d = OKLCh(L: 0.65, c: 0.15, h: 100)

        let h = PuzzleGradient(
            id: 0, dir: .h, len: 2,
            cells: [
                GradientCellSpec(r: 1, c: 0, pos: 0, color: a,
                                 locked: false, isIntersection: false),
                GradientCellSpec(r: 1, c: 1, pos: 1, color: shared,
                                 locked: true, isIntersection: true),
            ],
            colors: [a, shared])
        let v = PuzzleGradient(
            id: 1, dir: .v, len: 3,
            cells: [
                GradientCellSpec(r: 0, c: 1, pos: 0, color: b,
                                 locked: false, isIntersection: false),
                GradientCellSpec(r: 1, c: 1, pos: 1, color: shared,
                                 locked: false, isIntersection: true),
                GradientCellSpec(r: 2, c: 1, pos: 2, color: d,
                                 locked: false, isIntersection: false),
            ],
            colors: [b, shared, d])

        var grads = [h, v]
        normalizeSharedCellLocks(&grads)

        // Locked in any copy means locked in all of them, so the bank
        // builder and the board grid can no longer disagree.
        let sharedFlags = grads.flatMap { g in
            g.cells.filter { $0.r == 1 && $0.c == 1 }.map { $0.locked }
        }
        XCTAssertEqual(sharedFlags, [true, true])

        // Nothing else changes: unlocked cells stay unlocked.
        XCTAssertFalse(grads[0].cells[0].locked)
        XCTAssertFalse(grads[1].cells[0].locked)
        XCTAssertFalse(grads[1].cells[2].locked)

        // Idempotent, and a puzzle with no split flags is untouched.
        var again = grads
        normalizeSharedCellLocks(&again)
        XCTAssertEqual(again, grads)
    }
}
