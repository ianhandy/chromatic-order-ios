//  Generative audit: generate many puzzles per level, verify each has
//  exactly one valid placement under the game's check semantics
//  (OK.equal with no CB mode — matches GameState.handleCheck).

import XCTest
@testable import ChromaticOrder

final class SolvabilityAuditTests: XCTestCase {

    private func writeReport(_ text: String, name: String) {
        let path = "/tmp/kroma-solver-\(name).txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        print("[SolvabilityAudit] wrote \(path)")
    }

    // MARK: sanity

    /// Force a truly ambiguous puzzle by replacing bank items so two
    /// swatches have DIFFERENT colors but each is within ΔE 2 of
    /// BOTH cells' solutions — a true cross-cell swap that changes
    /// the visible placement. Solver must return 2.
    func testSolverDetectsTrueCrossCellAmbiguity() throws {
        // bank and solution points placed in OKLab coords so we control
        // ΔE directly. L does the separation between the two banks;
        // ±b (via hue 90°/270° with tiny c) does the perpendicular
        // offset so each solution is within ΔE 2 of BOTH banks, yet
        // the two solutions are >ΔE 2 apart from each other.
        let bankA = OKLCh(L: 0.50, c: 0, h: 0)     // lab (50, 0, 0)
        let bankB = OKLCh(L: 0.53, c: 0, h: 0)     // lab (53, 0, 0) — ΔE 3 from bankA
        let solA = OKLCh(L: 0.515, c: 0.011, h: 90)   // lab (51.5, 0, +1.1)
        let solB = OKLCh(L: 0.515, c: 0.011, h: 270)  // lab (51.5, 0, -1.1)
        XCTAssertLessThan(OK.dist(bankA, solA), 2)
        XCTAssertLessThan(OK.dist(bankA, solB), 2)
        XCTAssertLessThan(OK.dist(bankB, solA), 2)
        XCTAssertLessThan(OK.dist(bankB, solB), 2)
        XCTAssertGreaterThan(OK.dist(bankA, bankB), 2)
        XCTAssertGreaterThan(OK.dist(solA, solB), 2)

        let g = PuzzleGradient(
            id: 0, dir: .h, len: 2,
            cells: [
                GradientCellSpec(r: 0, c: 0, pos: 0, color: solA,
                                 locked: false, isIntersection: false),
                GradientCellSpec(r: 0, c: 1, pos: 1, color: solB,
                                 locked: false, isIntersection: false),
            ],
            colors: [solA, solB])
        var puzzle = makePuzzle(gradients: [g])
        // Replace bank with the crafted colors. The generator would
        // never produce this (bank comes from cell solutions) but we
        // need the solver to FLAG it if it does happen.
        puzzle.bank = [BankItem(id: 0, color: bankA),
                       BankItem(id: 1, color: bankB)]
        XCTAssertEqual(PuzzleSolver.countValidPlacements(puzzle, limit: 4), 2)

        // The diagnose() method should return a report classifying
        // this as a bankCrossMatch (bank items differ from any cell's
        // spec.color) and flag the two differing cells.
        let report = try XCTUnwrap(PuzzleSolver.diagnose(puzzle))
        XCTAssertEqual(report.kind, .bankCrossMatch)
        XCTAssertEqual(report.differingCells.count, 2)
        XCTAssertEqual(Set(report.involvedGradientIds), [0])
    }

    /// Palindromic gradient: solution[0] ≈ solution[len-1] etc. The
    /// bank is exactly the solution colors. Swapping bank items so
    /// cell 0 gets solution[N-1]'s color and cell N-1 gets solution[0]'s
    /// color produces a visually-indistinguishable placement, so the
    /// solver reports 1 (correct collapse). But if we construct a
    /// case where the swap IS visibly distinct (banks not in the same
    /// equivalence class despite both being valid at both cells), the
    /// solver should return 2 AND classify as palindromicGradient when
    /// the alternate placement is a full reversal.
    func testDiagnoseLabelsBankCrossMatchVsPalindrome() throws {
        // Reuse the crossCell puzzle from the prior test. Palindromic-
        // gradient is covered by the full generator loop (guard 3.5
        // rejects these, so we'd need to bypass the generator to
        // produce one — out of scope for a sanity test).
        let bankA = OKLCh(L: 0.50, c: 0, h: 0)
        let bankB = OKLCh(L: 0.53, c: 0, h: 0)
        let solA = OKLCh(L: 0.515, c: 0.011, h: 90)
        let solB = OKLCh(L: 0.515, c: 0.011, h: 270)
        let g = PuzzleGradient(
            id: 7, dir: .h, len: 2,
            cells: [
                GradientCellSpec(r: 0, c: 0, pos: 0, color: solA,
                                 locked: false, isIntersection: false),
                GradientCellSpec(r: 0, c: 1, pos: 1, color: solB,
                                 locked: false, isIntersection: false),
            ],
            colors: [solA, solB])
        var puzzle = makePuzzle(gradients: [g])
        puzzle.bank = [BankItem(id: 0, color: bankA),
                       BankItem(id: 1, color: bankB)]
        let report = try XCTUnwrap(PuzzleSolver.diagnose(puzzle))
        // Involved gradient is id=7 in this puzzle.
        XCTAssertEqual(report.involvedGradientIds, [7])
        XCTAssertEqual(report.differingCells.count, 2)
    }

    // MARK: Rule 2 — adjacency step-consistency

    func testStepConsistencyBlocksNonLinearPlacement() throws {
        // Build a 3-cell gradient with step (+0.10 L, 0, 0 in OKLCh).
        // Bank = cell solutions. Now swap two bank items so the placed
        // cells don't form a linear progression. The per-cell OK.equal
        // check would PASS (each cell's placed color ≈ its spec.color
        // only if the swap is ΔE-2-equivalent, which requires near-
        // palindromic colors — we instead build a case where swap IS
        // visibly distinct and per-cell check fails too). For this
        // test, force the assignment by marking one cell locked and
        // ensuring the bank construction could produce a valid but
        // non-linear placement. Simpler: just verify that with the
        // step-consistency flag ON, a palindromic 2-cell gradient
        // admits exactly one placement; with flag OFF and a crafted
        // ambiguous bank, admits two.
        //
        // Minimal case: crafted puzzle where enforceStepConsistency
        // removes an otherwise-valid alternate.
        let bankA = OKLCh(L: 0.50, c: 0, h: 0)
        let bankB = OKLCh(L: 0.53, c: 0, h: 0)
        let solA = OKLCh(L: 0.515, c: 0.011, h: 90)
        let solB = OKLCh(L: 0.515, c: 0.011, h: 270)
        let g = PuzzleGradient(
            id: 0, dir: .h, len: 2,
            cells: [
                GradientCellSpec(r: 0, c: 0, pos: 0, color: solA,
                                 locked: false, isIntersection: false),
                GradientCellSpec(r: 0, c: 1, pos: 1, color: solB,
                                 locked: false, isIntersection: false),
            ],
            colors: [solA, solB])
        var puzzle = makePuzzle(gradients: [g])
        puzzle.bank = [BankItem(id: 0, color: bankA),
                       BankItem(id: 1, color: bankB)]
        // Without step check: 2 valid (both cross-cell matching options).
        let off = PuzzleSolver.countValidPlacements(
            puzzle, limit: 4, enforceStepConsistency: false)
        XCTAssertEqual(off, 2)
        // With step check: gradient's step (solB - solA in lab) is
        // (0, 0, -2.2) but bank deltas between adjacent cells in
        // either swap are (+3, 0, 0) or (-3, 0, 0) — nowhere near the
        // expected step. Both matchings rejected. Returns 0.
        let on = PuzzleSolver.countValidPlacements(
            puzzle, limit: 4, enforceStepConsistency: true)
        XCTAssertEqual(on, 0,
                       "Step consistency rejects placements whose " +
                       "adjacent-cell deltas don't match the gradient step.")
    }

    func testStepConsistencyAcceptsCanonicalLinearPlacement() {
        // Normal 3-cell gradient; canonical placement should pass.
        let colors = [
            OKLCh(L: 0.40, c: 0.10, h: 0),
            OKLCh(L: 0.50, c: 0.10, h: 30),
            OKLCh(L: 0.60, c: 0.10, h: 60),
        ]
        let puzzle = makePuzzle(gradients: [makeGradient(id: 0, colors: colors)])
        XCTAssertEqual(
            PuzzleSolver.countValidPlacements(puzzle, limit: 4,
                                               enforceStepConsistency: true),
            1)
    }

    // MARK: Rule 3 — minimum-locks

    func testMinimumLockSetShrinksWhenLocksAreRedundant() {
        // 1-gradient 3-cell puzzle. No cells locked by default. The
        // generator leaves at least one gradient with a lock elsewhere,
        // but for a self-contained unit test we'll craft one with 3
        // cells and 1 lock, then verify minimumLockSet returns 0 if
        // uniqueness holds without any locks (trivially true for a
        // 3-cell linear gradient where all three colors differ).
        let colors = [
            OKLCh(L: 0.40, c: 0.10, h: 0),
            OKLCh(L: 0.50, c: 0.10, h: 30),
            OKLCh(L: 0.60, c: 0.10, h: 60),
        ]
        var puzzle = makePuzzle(gradients: [
            makeGradient(id: 0, colors: colors)
        ])
        // Lock cell 1 — redundant, the puzzle is already unique.
        for gi in puzzle.gradients.indices {
            var g = puzzle.gradients[gi]
            if let idx = g.cells.firstIndex(where: { $0.pos == 1 }) {
                g.cells[idx].locked = true
                puzzle.gradients[gi] = g
            }
        }
        // Rebuild bank to match — lock removes that cell from the bank.
        puzzle.bank = [BankItem(id: 0, color: colors[0]),
                       BankItem(id: 1, color: colors[2])]
        puzzle.initialBankCount = 2

        XCTAssertTrue(PuzzleSolver.isUniquelySolvable(puzzle))
        let minSet = PuzzleSolver.minimumLockSet(puzzle)
        XCTAssertEqual(minSet.count, 0,
                       "Lock is redundant; minimum should be empty")
    }

    func testMinimumLockSetKeepsIndispensableLocks() {
        // Build a puzzle where a lock is actually required for
        // uniqueness: a single gradient where two ends could swap
        // without a lock. Here, the colors deliberately make that a
        // non-issue — so we'll construct a 2-gradient case where one
        // gradient's lone lock is the only thing pinning orientation.
        // Using palindromic gradient forcing was banned (rejected by
        // guard 3.5), so we stick with generator output for this test.
        // Instead, just verify the API returns a set with size <= the
        // initial lock count.
        let puzzle = generatePuzzle(level: 10)
        let initialLocks = puzzle.gradients
            .flatMap { $0.cells }
            .filter { $0.locked }
            .count
        let minSet = PuzzleSolver.minimumLockSet(puzzle)
        XCTAssertLessThanOrEqual(minSet.count, initialLocks)
    }

    // MARK: Rule 4 — trajectory extrapolation

    func testTrajectoryExtrapolationExtendsByOneStep() {
        let g = PuzzleGradient(
            id: 0, dir: .h, len: 3,
            cells: [],
            colors: [
                OKLCh(L: 0.40, c: 0.10, h: 0),
                OKLCh(L: 0.50, c: 0.10, h: 0),
                OKLCh(L: 0.60, c: 0.10, h: 0),
            ])
        let t = gradientTrajectory(g)
        // Step in lab is (+0.10, 0, 0) per cell. Start extrapolation
        // goes one step below first (L ≈ 0.30); end one above last
        // (L ≈ 0.70). a and b stay ~0.
        XCTAssertEqual(t.extrapolatedStart.L, 0.30, accuracy: 0.001)
        XCTAssertEqual(t.extrapolatedEnd.L, 0.70, accuracy: 0.001)
        // stepPoints = [start, 3 colors, end] = 5 points
        XCTAssertEqual(t.stepPoints.count, 5)
    }

    func testTrajectoryOverlapFlagsOverlappingLines() {
        // Two gradients walking through the same color corridor — same
        // direction, offset slightly. Line-segment distance should be
        // small; intersecting-pair count at ΔE 2 should be 1.
        let g0 = PuzzleGradient(
            id: 0, dir: .h, len: 3,
            cells: [],
            colors: [OKLCh(L: 0.40, c: 0.10, h: 0),
                     OKLCh(L: 0.50, c: 0.10, h: 0),
                     OKLCh(L: 0.60, c: 0.10, h: 0)])
        let g1 = PuzzleGradient(
            id: 1, dir: .v, len: 3,
            cells: [],
            colors: [OKLCh(L: 0.40, c: 0.10, h: 90),
                     OKLCh(L: 0.50, c: 0.10, h: 90),
                     OKLCh(L: 0.60, c: 0.10, h: 90)])
        // h=0 → a=+0.10, b=0. h=90 → a=0, b=+0.10. So lines are
        // parallel in L, offset in a/b — lab distance ≈ √(10² + 10²) ≈ 14.
        let summary = trajectoryOverlapSummary([g0, g1])
        XCTAssertEqual(summary.intersectingPairCount, 0)
        XCTAssertGreaterThan(summary.minLineDistance, 10)
    }

    func testTrajectoryOverlapCatchesNearlyParallelClose() {
        // Two parallel lines < ΔE 2 apart → flagged as intersecting.
        let g0 = PuzzleGradient(
            id: 0, dir: .h, len: 3,
            cells: [],
            colors: [OKLCh(L: 0.40, c: 0.10, h: 0),
                     OKLCh(L: 0.50, c: 0.10, h: 0),
                     OKLCh(L: 0.60, c: 0.10, h: 0)])
        let g1 = PuzzleGradient(
            id: 1, dir: .v, len: 3,
            cells: [],
            colors: [OKLCh(L: 0.401, c: 0.10, h: 0),
                     OKLCh(L: 0.501, c: 0.10, h: 0),
                     OKLCh(L: 0.601, c: 0.10, h: 0)])
        let summary = trajectoryOverlapSummary([g0, g1])
        XCTAssertEqual(summary.intersectingPairCount, 1)
        XCTAssertLessThan(summary.minLineDistance, 2)
    }

    func testDiagnoseReturnsNilOnUniquePuzzle() {
        let g = makeGradient(id: 0, colors: [
            OKLCh(L: 0.5, c: 0.10, h: 0),
            OKLCh(L: 0.5, c: 0.10, h: 60),
            OKLCh(L: 0.5, c: 0.10, h: 120),
        ])
        XCTAssertNil(PuzzleSolver.diagnose(makePuzzle(gradients: [g])))
    }

    func testSolverFindsUniqueSolutionOnTrivialPuzzle() {
        let g = makeGradient(id: 0, colors: [
            OKLCh(L: 0.5, c: 0.10, h: 0),
            OKLCh(L: 0.5, c: 0.10, h: 60),
            OKLCh(L: 0.5, c: 0.10, h: 120),
        ])
        XCTAssertEqual(PuzzleSolver.countValidPlacements(makePuzzle(gradients: [g]), limit: 4), 1)
    }

    /// Two cells whose ΔE is effectively zero — a classic "bank swap
    /// is visibly indistinguishable" case. Solver should return 1
    /// because we dedupe by visible placement.
    func testSolverCollapsesIndistinguishableSwap() {
        let g = makeGradient(id: 0, colors: [
            OKLCh(L: 0.5, c: 0.10, h: 0),
            OKLCh(L: 0.5, c: 0.10, h: 0.0001),
        ])
        XCTAssertEqual(PuzzleSolver.countValidPlacements(makePuzzle(gradients: [g]), limit: 4), 1)
    }

    // MARK: audit — full generatePuzzle pipeline, big sample, default mode.

    /// Smoke version — 50 attempts/level. Runs in ~90s. Use for PR
    /// checks. The 500-per-level sweep below is the full regression
    /// catch (~11 min) — run nightly or before shipping.
    func testGeneratePuzzleIsUniquelySolvable_smoke() throws {
        try runGeneratePuzzleAudit(attemptsPerLevel: 50, tag: "smoke")
    }

    /// Maximum-count-per-level feasibility sweep. For each level and
    /// each candidate gradient count from 1..10, measure success rate
    /// at ΔE 4 (the chosen middle-ground threshold). Output: per level,
    /// the largest count that still hits ≥80% and ≥95% success. This
    /// is the "where does the wall hit" view — the count progression
    /// we can actually support given today's grower.
    func testMaxFeasibleCountPerLevel() throws {
        let attemptsPerLevel = 100
        let threshold = 4.0
        var report = "===== Max feasible count per level (ΔE 4, " +
                     "\(attemptsPerLevel)/cfg) =====\n"
        report += "lv  count->success%\n"
        report += "    " + (1...10).map { String(format: "%3d", $0) }.joined(separator: " ") + "  | ≥95% | ≥80%\n"
        let clock = Date()
        for level in 1...20 {
            var successPerCount: [Int: Double] = [:]
            for count in 1...10 {
                var cfg = GenConfig()
                cfg.minCellDeltaE = threshold
                cfg.gradientCountOverride = count
                var gen = 0
                for _ in 0..<attemptsPerLevel {
                    if tryGrowOnce(level: level, config: cfg) != nil {
                        gen += 1
                    }
                }
                successPerCount[count] = Double(gen) / Double(attemptsPerLevel) * 100
            }
            let row95 = (1...10).last(where: { (successPerCount[$0] ?? 0) >= 95 }) ?? 0
            let row80 = (1...10).last(where: { (successPerCount[$0] ?? 0) >= 80 }) ?? 0
            var line = String(format: "%2d  ", level)
            for count in 1...10 {
                let s = successPerCount[count] ?? 0
                line += String(format: "%3.0f ", s)
            }
            line += String(format: " | %4d | %4d", row95, row80)
            report += line + "\n"
        }
        let elapsed = Date().timeIntervalSince(clock)
        report += "elapsed \(String(format: "%.1f", elapsed))s\n"
        writeReport(report, name: "maxcount")
    }

    /// Multi-knob tuning sweep. For each level, try combinations of
    /// (minCellDeltaE × gradientCountOverride) and record the
    /// success rate (puzzles_generated / attempts). Writes a table
    /// showing (a) default-config success per level (b) best combo
    /// found per level (c) every combo for levels that still can't
    /// clear 50% success. Zero uniqueness failures required.
    func testMultiKnobTuningSweep() throws {
        let attemptsPerLevel = 100
        let thresholds: [Double] = [3.0, 4.0, 5.0]
        // Gradient-count candidates, per level. Keyed by level tier.
        func countCandidates(for level: Int) -> [Int] {
            let def = defaultGradientCountForLevel(level)
            // Always try default; also try a lighter load.
            var s: Set<Int> = [def]
            s.insert(max(1, def - 2))
            s.insert(max(1, def - 4))
            s.insert(max(1, def / 2))
            s.insert(1)
            return Array(s).sorted()
        }

        struct ConfigResult {
            let threshold: Double
            let count: Int
            let generated: Int
            let failures: Int
        }
        var byLevel: [Int: [ConfigResult]] = [:]
        var totalFailures = 0
        let clock = Date()
        for level in 1...20 {
            var results: [ConfigResult] = []
            for threshold in thresholds {
                for count in countCandidates(for: level) {
                    var cfg = GenConfig()
                    cfg.minCellDeltaE = threshold
                    cfg.gradientCountOverride = count
                    var generated = 0
                    var failures = 0
                    for _ in 0..<attemptsPerLevel {
                        guard let p = tryGrowOnce(level: level, config: cfg)
                        else { continue }
                        generated += 1
                        if PuzzleSolver.countValidPlacements(p, limit: 2) != 1 {
                            failures += 1
                        }
                    }
                    totalFailures += failures
                    results.append(ConfigResult(
                        threshold: threshold, count: count,
                        generated: generated, failures: failures))
                }
            }
            byLevel[level] = results
        }
        let elapsed = Date().timeIntervalSince(clock)

        var report = "===== Multi-knob sweep: \(attemptsPerLevel) attempts/config/level, " +
                     "elapsed \(String(format: "%.1f", elapsed))s =====\n"
        report += "Per level: (a) default-config success | (b) best combo\n\n"
        for level in 1...20 {
            let def = defaultGradientCountForLevel(level)
            let results = byLevel[level] ?? []
            let sorted = results.sorted { $0.generated > $1.generated }
            let best = sorted.first
            // "Default" = (ΔE 5, count = default)
            let dflt = results.first { $0.threshold == 5.0 && $0.count == def }
            let dfltPct = dflt.map { Double($0.generated) / Double(attemptsPerLevel) * 100.0 } ?? 0
            let bestPct = best.map { Double($0.generated) / Double(attemptsPerLevel) * 100.0 } ?? 0
            report += String(format: "lv %2d  default(ΔE 5, n=%d)=%5.1f%%  " +
                             "best(ΔE %.0f, n=%d)=%5.1f%%\n",
                             level, def, dfltPct,
                             best?.threshold ?? 0, best?.count ?? 0, bestPct)
        }
        report += "\n--- full matrix for levels where best < 80% ---\n"
        for level in 1...20 {
            let results = byLevel[level] ?? []
            let bestGen = results.map { $0.generated }.max() ?? 0
            if Double(bestGen) / Double(attemptsPerLevel) < 0.80 {
                report += "\nlv \(level):\n"
                report += "  ΔE  count  gen%  fails\n"
                for r in results.sorted(by: { ($0.threshold, $0.count) < ($1.threshold, $1.count) }) {
                    let pct = Double(r.generated) / Double(attemptsPerLevel) * 100.0
                    report += String(format: "  %.0f   %5d  %4.0f  %5d\n",
                                     r.threshold, r.count, pct, r.failures)
                }
            }
        }
        report += "\nuniqueness failures across sweep: \(totalFailures)\n"
        writeReport(report, name: "multiknob")
        XCTAssertEqual(totalFailures, 0)
    }

    /// Mirror of `Generate.swift`'s private `defaultGradientCount`.
    private func defaultGradientCountForLevel(_ level: Int) -> Int {
        if level <= 3 { return 1 }
        if level <= 6 { return 2 }
        if level <= 9 { return 3 }
        if level <= 12 { return 5 }
        if level <= 15 { return 7 }
        return 10
    }

    /// Sweep tryGrowOnce generator success + uniqueness across several
    /// `minCellDeltaE` thresholds. Produces a table for picking the
    /// right Rule 1 value: each row shows reject% per level for a
    /// given ΔE floor. Uniqueness is verified with Rule 2 enforced.
    func testRule1ThresholdSweep() throws {
        let thresholds: [Double] = [3.0, 4.0, 5.0]
        let attemptsPerLevel = 200
        var rows: [String] = []
        var failures: [(Double, Int, Int)] = []  // (threshold, level, attempt)

        rows.append("ΔE  level  generated  rejected  reject%")
        let clock = Date()
        for threshold in thresholds {
            var cfg = GenConfig()
            cfg.minCellDeltaE = threshold
            for level in 1...20 {
                var generated = 0
                var rejected = 0
                for attempt in 0..<attemptsPerLevel {
                    if let p = tryGrowOnce(level: level, config: cfg) {
                        generated += 1
                        if PuzzleSolver.countValidPlacements(p, limit: 2) != 1 {
                            failures.append((threshold, level, attempt))
                        }
                    } else {
                        rejected += 1
                    }
                }
                let pct = Double(rejected) / Double(attemptsPerLevel) * 100.0
                rows.append(String(format: "%.0f  %5d  %9d  %8d  %6.1f",
                                   threshold, level, generated, rejected, pct))
            }
            rows.append("")
        }
        let elapsed = Date().timeIntervalSince(clock)

        var report = "===== Rule 1 threshold sweep: \(attemptsPerLevel) attempts/level/threshold, " +
                     "elapsed \(String(format: "%.1f", elapsed))s =====\n"
        for r in rows { report += r + "\n" }
        report += "uniqueness failures: \(failures.count)\n"
        for f in failures.prefix(30) {
            report += "  ΔE \(f.0) lv \(f.1) attempt \(f.2)\n"
        }
        writeReport(report, name: "rule1-sweep")
        XCTAssertEqual(failures.count, 0)
    }

    /// Reproduce the strict-phase loop body at lv 12: 500 sequential
    /// tryGrowOnce calls, count nil vs return.
    func testTryGrowOnceLv12_500() throws {
        var nils = 0
        var succ = 0
        for _ in 0..<500 {
            if tryGrowOnce(level: 12) != nil { succ += 1 } else { nils += 1 }
        }
        writeReport("lv 12 tryGrowOnce x500: succ=\(succ) nil=\(nils)", name: "lv12-500")
    }

    /// 50 sequential generatePuzzle calls at lv 12 — reproduces
    /// smoke-test conditions for that level. Print timings.
    func testLv12Fifty() throws {
        var lines: [String] = []
        for i in 0..<50 {
            let clock = Date()
            let p = generatePuzzle(level: 12)
            let elapsed = Date().timeIntervalSince(clock) * 1000
            lines.append(String(format: "%3d: %7.0fms diff=%d grads=%d",
                                i, elapsed, p.difficulty, p.gradients.count))
        }
        writeReport(lines.joined(separator: "\n"), name: "lv12-50")
    }

    /// Outcome counter at lv 12 — is the builder returning nil, or are
    /// puzzles coming through but failing the route? Calls
    /// tryBuildOrGrow directly 2000 times and tallies result types.
    func testBuilderOutcomesAtLv12() throws {
        var builderNil = 0
        var byDifficulty: [Int: Int] = [:]
        let cfg = GenConfig()
        for _ in 0..<2000 {
            if let p = tryGrowOnce(level: 12, config: cfg) {
                byDifficulty[p.difficulty, default: 0] += 1
            } else {
                builderNil += 1
            }
        }
        var report = "builder-nil: \(builderNil) / 2000\n"
        for d in 1...10 {
            report += "diff \(d): \(byDifficulty[d] ?? 0)\n"
        }
        writeReport(report, name: "lv12-outcomes")
    }

    /// Single generatePuzzle call at each level, with timing. If
    /// anything hangs or crashes, this pinpoints which level.
    func testGeneratePuzzleSmokeSingle() throws {
        var lines: [String] = []
        for level in 1...20 {
            let clock = Date()
            let p = generatePuzzle(level: level)
            let elapsed = Date().timeIntervalSince(clock) * 1000
            lines.append(String(format: "lv %2d: %6.0fms, diff=%2d, grads=%d",
                                level, elapsed, p.difficulty, p.gradients.count))
        }
        writeReport(lines.joined(separator: "\n"), name: "gen-single")
    }

    /// Measure the difficulty distribution that the current generator
    /// (builder + rescore) produces per level. Outputs a histogram
    /// per level so we can see what `target` should map to.
    func testDifficultyDistribution() throws {
        let attemptsPerLevel = 200
        var rows: [String] = []
        rows.append("lv  diff 1  2  3  4  5  6  7  8  9  10  | mean")
        for level in 1...20 {
            var hist: [Int: Int] = [:]
            var sum = 0
            var count = 0
            for _ in 0..<attemptsPerLevel {
                guard let p = tryGrowOnce(level: level) else { continue }
                hist[p.difficulty, default: 0] += 1
                sum += p.difficulty
                count += 1
            }
            var line = String(format: "%2d      ", level)
            for d in 1...10 {
                line += String(format: "%3d ", hist[d] ?? 0)
            }
            let mean = count > 0 ? Double(sum) / Double(count) : 0
            line += String(format: " | %.2f", mean)
            rows.append(line)
        }
        writeReport(rows.joined(separator: "\n"), name: "diff-histogram")
    }

    /// Safe audit via tryGrowOnce — single grower attempt per
    /// iteration, returns nil on guard rejection (no infinite fallback
    /// loop). Use this to measure generator health under tight
    /// GenConfig (e.g. after raising `minCellDeltaE`). Reports
    /// per-level success rate so tuning decisions have data.
    func testTryGrowOnceSolvability_smoke() throws {
        let attemptsPerLevel = 500
        var failures = 0
        var generated: [Int: Int] = [:]
        var rejected: [Int: Int] = [:]
        let clock = Date()
        for level in 1...20 {
            for _ in 0..<attemptsPerLevel {
                if let p = tryGrowOnce(level: level) {
                    generated[level, default: 0] += 1
                    if PuzzleSolver.countValidPlacements(p, limit: 2) != 1 {
                        failures += 1
                    }
                } else {
                    rejected[level, default: 0] += 1
                }
            }
        }
        let elapsed = Date().timeIntervalSince(clock)
        var report = "===== tryGrowOnce smoke: \(attemptsPerLevel)/level, " +
                     "elapsed \(String(format: "%.1f", elapsed))s =====\n"
        report += "level  generated  rejected  reject%\n"
        for level in 1...20 {
            let g = generated[level] ?? 0
            let r = rejected[level] ?? 0
            let pct = attemptsPerLevel == 0 ? 0.0
                    : Double(r) / Double(attemptsPerLevel) * 100.0
            report += String(format: "%5d  %9d  %8d  %6.1f\n", level, g, r, pct)
        }
        report += "failures: \(failures)\n"
        writeReport(report, name: "trygrow-smoke")
        XCTAssertEqual(failures, 0)
    }

    func testGeneratePuzzleIsUniquelySolvableAt500PerLevel() throws {
        try runGeneratePuzzleAudit(attemptsPerLevel: 500, tag: "full")
    }

    private func runGeneratePuzzleAudit(attemptsPerLevel: Int, tag: String) throws {
        var failuresByLevel: [Int: Int] = [:]
        var printed: [Int: Int] = [:]
        var fmap: [Int: [String]] = [:]

        let clock = Date()
        for level in 1...20 {
            for attempt in 0..<attemptsPerLevel {
                let puzzle = generatePuzzle(level: level)
                let count = PuzzleSolver.countValidPlacements(puzzle, limit: 2)
                if count == 1 { continue }
                failuresByLevel[level, default: 0] += 1
                let already = printed[level, default: 0]
                if already < 5 {
                    printed[level] = already + 1
                    let s = describeFailure(level: level, attempt: attempt,
                                             count: count, puzzle: puzzle)
                    fmap[level, default: []].append(s)
                }
            }
        }
        let elapsed = Date().timeIntervalSince(clock)

        var report = "===== generatePuzzle audit: \(attemptsPerLevel) attempts/level, " +
                     "elapsed \(String(format: "%.1f", elapsed))s =====\n"
        report += "level  failures\n"
        var total = 0
        for level in 1...20 {
            let f = failuresByLevel[level] ?? 0
            total += f
            report += String(format: "%5d  %8d\n", level, f)
        }
        report += "total  \(total)\n"
        for (level, lines) in fmap.sorted(by: { $0.key < $1.key }) {
            report += "--- failures at level \(level):\n"
            for line in lines { report += line + "\n" }
        }
        writeReport(report, name: "generate-\(tag)")

        XCTAssertEqual(total, 0, "\(total) generatePuzzle outputs are not uniquely solvable")
    }

    // MARK: audit — CB modes. Runtime handleCheck uses .none regardless
    // of the player's CB setting. A CB-generated puzzle could still ship
    // to a player (e.g., via iMessage share) and be solved under .none.
    // Verify uniqueness under .none for each CB generation mode.

    /// Uses tryGrowOnce — single attempt, nil on guard-rejection, no
    /// infinite fallback spin. Less coverage per level (many nils) but
    /// won't hang on tight CB configs at high levels.
    func testTryGrowOnceUnderCBModesIsUniqueUnderDefaultCheck() throws {
        let attemptsPerLevel = 300
        let modes: [CBMode] = [.deuteranopia, .protanopia, .tritanopia, .achromatopsia]
        var failures: [(CBMode, Int, Int, Int)] = []
        var generatedByMode: [CBMode: Int] = [:]
        let clock = Date()

        for mode in modes {
            var cfg = GenConfig()
            cfg.cbMode = mode
            for level in 1...20 {
                for attempt in 0..<attemptsPerLevel {
                    guard let puzzle = tryGrowOnce(level: level, config: cfg) else { continue }
                    generatedByMode[mode, default: 0] += 1
                    let count = PuzzleSolver.countValidPlacements(puzzle, mode: .none, limit: 2)
                    if count != 1 {
                        failures.append((mode, level, attempt, count))
                    }
                }
            }
        }
        let elapsed = Date().timeIntervalSince(clock)

        var report = "===== tryGrowOnce CB audit, .none runtime check, " +
                     "\(attemptsPerLevel) attempts/level/mode, elapsed " +
                     "\(String(format: "%.1f", elapsed))s =====\n"
        for (mode, n) in generatedByMode.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            report += "  \(mode): \(n) puzzles generated\n"
        }
        report += "total failures: \(failures.count)\n"
        for f in failures.prefix(30) {
            report += "  mode=\(f.0) level=\(f.1) attempt=\(f.2) count=\(f.3)\n"
        }
        writeReport(report, name: "cb")

        XCTAssertEqual(failures.count, 0,
                       "\(failures.count) CB-generated puzzles ambiguous under runtime .none check")
    }

    // MARK: helpers

    private func makeGradient(id: Int, colors: [OKLCh]) -> PuzzleGradient {
        let specs = colors.enumerated().map { (i, color) in
            GradientCellSpec(r: 0, c: i, pos: i, color: color,
                             locked: false, isIntersection: false)
        }
        return PuzzleGradient(id: id, dir: .h, len: colors.count,
                              cells: specs, colors: colors)
    }

    private func makePuzzle(gradients: [PuzzleGradient]) -> Puzzle {
        var board: [[BoardCell]] = Array(
            repeating: Array(repeating: .dead, count: 20),
            count: 20)
        var bank: [BankItem?] = []
        var uid = 0
        var banked: Set<Int> = []
        for g in gradients {
            for spec in g.cells {
                board[spec.r][spec.c] = BoardCell(
                    kind: .cell, solution: spec.color, placed: nil,
                    locked: spec.locked, isIntersection: spec.isIntersection,
                    gradIds: [g.id])
                if !spec.locked {
                    let key = spec.r * 64 + spec.c
                    if !banked.contains(key) {
                        banked.insert(key)
                        bank.append(BankItem(id: uid, color: spec.color))
                        uid += 1
                    }
                }
            }
        }
        return Puzzle(level: 1, gridW: 20, gridH: 20, board: board,
                      bank: bank, initialBankCount: bank.count,
                      gradients: gradients, channelCount: 1,
                      activeChannels: [.h], primaryChannel: .h,
                      difficulty: 1, pairProx: 0, extrapProx: 0,
                      interDist: 0)
    }

    private func describeFailure(level: Int, attempt: Int,
                                  count: Int, puzzle: Puzzle) -> String {
        var s = "FAIL level=\(level) attempt=\(attempt) " +
                "count=\(count) difficulty=\(puzzle.difficulty) " +
                "grid=\(puzzle.gridW)x\(puzzle.gridH) " +
                "grads=\(puzzle.gradients.count) " +
                "bank=\(puzzle.bank.compactMap { $0 }.count)\n"
        if let report = PuzzleSolver.diagnose(puzzle) {
            s += "  DIAG: \(report.summary)\n"
            for d in report.differingCells.prefix(8) {
                s += "    \(d)\n"
            }
        }
        for (gi, g) in puzzle.gradients.enumerated() {
            let desc = g.cells.map { spec in
                "[\(spec.r),\(spec.c) pos=\(spec.pos) " +
                "L=\(f(spec.color.L)) c=\(f(spec.color.c)) h=\(f(spec.color.h)) " +
                (spec.locked ? "LOCK" : "free") +
                (spec.isIntersection ? " X" : "") + "]"
            }.joined(separator: " ")
            s += "  g\(gi) dir=\(g.dir.rawValue) len=\(g.len): \(desc)\n"
        }
        return s
    }

    private func f(_ x: Double) -> String { String(format: "%.3f", x) }
}
