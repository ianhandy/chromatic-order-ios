//  Can a person actually solve these, as opposed to a search?
//
//  `PuzzleSolver.isUniquelySolvable` only promises that exactly one
//  arrangement is valid. It says nothing about whether a player could ever
//  find it: a board with no given cells can still have a single solution
//  reachable only by exhaustive search, which no one is going to run in their
//  head.
//
//  A player never sees an empty cell's colour, so they cannot match a swatch
//  against a target. They sort:
//
//    partition  group the swatches by which run they belong to, which works
//               while the runs sit in different colour families,
//    order      arrange each group along its ramp, which works while
//               consecutive steps beat the eye's noise,
//    orient     decide which way round the run goes, which needs an anchor: a
//               given cell on the run, or a cell shared with a run already
//               placed, which inherits one.
//
//  Orientation is the one that can go missing, so it is what this file gates.
//  Deduction is a bonus channel on top (two known cells on a run fix its whole
//  ramp, and a shared cell carries that into a crossing run, like a crossword),
//  and its coverage is reported here for tuning rather than enforced.
//
//  An earlier version of this file gated on colour margin instead, demanding a
//  wide gap wherever deduction could not reach. That was wrong: a wide gap does
//  not help you place a cell you cannot compute, because there is nothing on
//  screen to compare the swatch against. tools/campaign/build.py builds levels
//  to satisfy the orientation rule; here we check the shipped result.

import XCTest
@testable import ChromaticOrder

final class CampaignFairnessTests: XCTestCase {

    /// Cells a player can compute instead of recognise: repeatedly, any
    /// gradient holding two known cells gives up the rest of its ramp.
    private func deductionClosure(_ puzzle: Puzzle, given: Set<CellIndex>) -> Set<CellIndex> {
        var known = given
        var changed = true
        while changed {
            changed = false
            for grad in puzzle.gradients {
                let cells = grad.cells.map { CellIndex(r: $0.r, c: $0.c) }
                guard cells.filter({ known.contains($0) }).count >= 2 else { continue }
                for cell in cells where !known.contains(cell) {
                    known.insert(cell)
                    changed = true
                }
            }
        }
        return known
    }

    /// The gap between a cell's own colour and the nearest other colour on the
    /// board: what the eye has to resolve when deduction cannot help.
    private func rivalMargins(_ puzzle: Puzzle) -> [CellIndex: Double] {
        var board: [CellIndex: OKLCh] = [:]
        for grad in puzzle.gradients {
            for spec in grad.cells {
                board[CellIndex(r: spec.r, c: spec.c)] = spec.color
            }
        }
        let keys = Array(board.keys)
        var out: [CellIndex: Double] = [:]
        for (i, cell) in keys.enumerated() {
            var closest = Double.greatestFiniteMagnitude
            for (j, other) in keys.enumerated() where i != j {
                closest = min(closest, OK.dist(board[cell]!, board[other]!))
            }
            out[cell] = closest
        }
        return out
    }

    func testDeductionCoverageReport() throws {
        var stats: [(index: Int, name: String, deduced: Int, byEye: Int, worst: Double)] = []

        for entry in CampaignCatalog.levels {
            guard let puzzle = entry.puzzle() else {
                XCTFail("level \(entry.index) (\(entry.name)) failed to rebuild")
                continue
            }
            var given: Set<CellIndex> = []
            var free: Set<CellIndex> = []
            for grad in puzzle.gradients {
                for spec in grad.cells {
                    let cell = CellIndex(r: spec.r, c: spec.c)
                    if spec.locked { given.insert(cell) } else { free.insert(cell) }
                }
            }
            let reachable = deductionClosure(puzzle, given: given)
            let margins = rivalMargins(puzzle)
            let byEye = free.subtracting(reachable)

            var worst = Double.greatestFiniteMagnitude
            for cell in byEye {
                worst = min(worst, margins[cell] ?? .greatestFiniteMagnitude)
            }
            stats.append((entry.index, entry.name, free.count - byEye.count,
                          byEye.count, worst == .greatestFiniteMagnitude ? 0 : worst))
        }

        let report = stats.map {
            String(format: "%3d %-12@ deduced %2d  by eye %2d  worst %.1f",
                   $0.index, $0.name as NSString, $0.deduced, $0.byEye, $0.worst)
        }.joined(separator: "\n")
        try? report.write(toFile: "/tmp/kroma-fairness.txt", atomically: true, encoding: .utf8)
        print("[CampaignFairness] wrote /tmp/kroma-fairness.txt")

        XCTAssertEqual(stats.count, CampaignCatalog.count,
                       "the report measured nothing, so it proves nothing")

        // A cell the player must resolve by eye is one the board gives them no
        // way to compute, so the only thing standing between them and a guess
        // is how far its colour sits from its nearest rival. `build.py` holds
        // that gap above its `eye_floor`; this re-checks the shipped result in
        // the app's own colour code, where the JND is 2 (`OK.equal`). The bar
        // here is twice that: a call inside two JNDs is not a call.
        let eyeFloor = 4.0
        let tooFine = stats.filter { $0.byEye > 0 && $0.worst < eyeFloor }
        XCTAssertTrue(tooFine.isEmpty,
                      "levels asking the eye for a call finer than ΔE \(eyeFloor):\n"
                      + tooFine.map { "\($0.index) \($0.name): worst ΔE \($0.worst)" }
                        .joined(separator: "\n"))
    }

    /// The campaign has to get harder, and the resource has to say so.
    ///
    /// This is the failure the playtest harness found and the reason the late
    /// chapters were rebuilt. Landmarks and Mastery were measuring 7.6 and
    /// 10.5 wrong cells for a typical eye while Workshop — the chapter that
    /// follows them — measured 1.7. Levels 71 to 100 were four times harder
    /// than anything after them, including the finale, and nothing in the
    /// build or the test suite noticed, because difficulty was recorded and
    /// never asserted.
    ///
    /// Two things are checked, and they fail for different reasons. The
    /// targets themselves must ramp: that is the curve, and a wall in the
    /// middle of it is an authoring mistake. And each level must have landed
    /// near its own target: that is the resource, and a level far off it means
    /// `campaign.json` no longer matches the tools that made it — which is how
    /// a hand-edited or half-regenerated file goes unnoticed.
    ///
    /// `tools/campaign/check_difficulty.py` is the other half of this: it
    /// re-measures every board from scratch rather than trusting the recorded
    /// number, which is the only way to catch the build agreeing with itself.
    func testDifficultyStaysOnItsCurve() throws {
        // Wider than the search's own tolerance, for the same reason
        // check_difficulty.py's is: a shape that cannot reach its target
        // inside the bank window keeps the closest it managed, and that is a
        // fact about the shape rather than a fault.
        let tolerance = 1.5

        var drifted: [String] = []
        var ceilingByChapter: [(chapter: String, target: Double)] = []

        for entry in CampaignCatalog.levels {
            guard let target = entry.difficultyTarget else {
                // The three teaching chapters are built to no target. They
                // measure essentially zero wrong cells, which is what a
                // teaching chapter should measure.
                XCTAssertLessThanOrEqual(
                    entry.index, 32,
                    "level \(entry.index) (\(entry.name)) carries no difficulty "
                    + "target, but everything past the teaching chapters is "
                    + "built to one")
                continue
            }
            guard let measured = entry.typicalWrong else {
                XCTFail("level \(entry.index) (\(entry.name)) declares a target "
                        + "but records no measurement")
                continue
            }
            if abs(measured - target) > tolerance {
                drifted.append("\(entry.index) \(entry.name): records \(measured) "
                               + "wrong against a target of \(target)")
            }
            if ceilingByChapter.last?.chapter != entry.chapter {
                ceilingByChapter.append((entry.chapter, target))
            } else {
                ceilingByChapter[ceilingByChapter.count - 1].target =
                    max(ceilingByChapter[ceilingByChapter.count - 1].target, target)
            }
        }

        XCTAssertTrue(drifted.isEmpty,
                      "levels that are not on the curve they were built to:\n"
                      + drifted.joined(separator: "\n"))

        // Each chapter may peak higher than the last one did. It may not peak
        // lower: that is the wall.
        for (earlier, later) in zip(ceilingByChapter, ceilingByChapter.dropFirst()) {
            XCTAssertLessThanOrEqual(
                earlier.target, later.target,
                "\(earlier.chapter) peaks at \(earlier.target) wrong cells but "
                + "\(later.chapter), which comes after it, peaks at "
                + "\(later.target) — the campaign gets easier as it goes")
        }
    }

    /// The board must have one answer a person can *arrive at*, not merely one
    /// answer a search can verify.
    ///
    /// `PuzzleSolver.isUniquelySolvable` — which `CampaignAuditTests` runs
    /// over every level — compares exact colours, so it happily passes a board
    /// carrying a second arrangement that differs from the authored one by
    /// less than anyone can see. The campaign shipped five such levels. On
    /// Harbor, two masts of equal length hang off one given cell and can trade
    /// their colours outright: every run stays an even walk, the given cell
    /// does not move, and the player is guessing between two boards the app
    /// scores differently.
    ///
    /// Three constructions are tried here, the three a player falls into
    /// without looking for them: two swatches trading places, two equal-length
    /// runs trading families, and a run laid down backwards. They are the same
    /// three `_alternative_arrangement` in tools/campaign/playtest.py builds,
    /// so the shipping gate and the authoring gate refuse the same boards.
    /// Between them they catch all five levels the campaign was shipping
    /// before this repair: 36 Rocket, 61 Frog, 66 Spider, 74 Castle and
    /// 85 Harbor.
    func testNoLevelHasAnIndistinguishableAlternative() throws {
        var unfair: [String] = []

        for entry in CampaignCatalog.levels {
            guard let puzzle = entry.puzzle() else { continue }

            var truth: [CellIndex: OKLCh] = [:]
            var locked: Set<CellIndex> = []
            var runs: [[CellIndex]] = []
            for grad in puzzle.gradients {
                var path: [CellIndex] = []
                for spec in grad.cells {
                    let cell = CellIndex(r: spec.r, c: spec.c)
                    truth[cell] = spec.color
                    if spec.locked { locked.insert(cell) }
                    path.append(cell)
                }
                runs.append(path)
            }
            let free = truth.keys.filter { !locked.contains($0) }.sorted {
                ($0.r, $0.c) < ($1.r, $1.c)
            }
            // A player's other expectation, beyond each run being even: the
            // runs on one board step at similar rates, because every board
            // they have seen does. An alternative that keeps every run even
            // but gives one of them a step nothing like the rest reads as
            // wrong, so it is not a board anybody is fooled by.
            let ceiling = stepOddity(runs, truth) * 1.25 + 0.5

            func admits(_ trial: [CellIndex: OKLCh], oddityMatters: Bool = true) -> Bool {
                guard trial.contains(where: { !OK.equal($0.value, truth[$0.key]!) })
                else { return false }          // not a different board at all
                guard locked.allSatisfy({ OK.equal(trial[$0]!, truth[$0]!) })
                else { return false }          // a given cell moved
                if oddityMatters, stepOddity(runs, trial) > ceiling { return false }
                return isEvenWalk(runs, trial)
            }

            // Two swatches trading places. Undetectable whenever both cells
            // sit only on runs that stay even afterwards, which is automatic
            // for a two-cell run, since any two colours are an even walk.
            var found: String? = nil
            outer: for i in 0..<free.count {
                for j in (i + 1)..<free.count {
                    guard !OK.equal(truth[free[i]]!, truth[free[j]]!) else { continue }
                    var trial = truth
                    trial[free[i]] = truth[free[j]]
                    trial[free[j]] = truth[free[i]]
                    if admits(trial) {
                        found = "swap \(free[i]) with \(free[j])"
                        break outer
                    }
                }
            }

            // Two runs of the same length trading their whole families, which
            // no swap can express and no reversal can reach. Only the free
            // cells move, so a given cell is never disturbed — and where the
            // two runs hang off a shared given cell, that cell keeps its
            // colour and says nothing about which family belongs where.
            if found == nil {
                outer2: for a in 0..<runs.count {
                    for b in (a + 1)..<runs.count {
                        let fa = runs[a].filter { !locked.contains($0) && !runs[b].contains($0) }
                        let fb = runs[b].filter { !locked.contains($0) && !runs[a].contains($0) }
                        guard !fa.isEmpty, fa.count == fb.count else { continue }
                        for source in [fb, fb.reversed()] {
                            var trial = truth
                            for (ca, cb) in zip(fa, source) {
                                trial[ca] = truth[cb]
                                trial[cb] = truth[ca]
                            }
                            if admits(trial) {
                                found = "runs \(a) and \(b) trade families"
                                break outer2
                            }
                        }
                    }
                }
            }

            // A run laid down backwards. Reversing an even walk leaves it even,
            // so the only things that can rule it out are a given cell moving
            // or a crossing run being dragged off its own line — which is what
            // `admits` tests. The step-oddity ceiling is deliberately *not*
            // applied here, to match `_alternative_arrangement` in
            // tools/campaign/playtest.py: that is the rule the boards were
            // authored against, and a backstop that forgave more than the
            // author's own rule would let a board through that the build had
            // already refused.
            if found == nil {
                for (a, path) in runs.enumerated() {
                    var trial = truth
                    for (pos, cell) in path.enumerated() {
                        trial[cell] = truth[path[path.count - 1 - pos]]
                    }
                    if admits(trial, oddityMatters: false) {
                        found = "run \(a) reversed"
                        break
                    }
                }
            }

            if let found {
                unfair.append("\(entry.index) \(entry.name): \(found) — every run "
                              + "stays an even walk, so nothing on screen tells "
                              + "the player which board is the answer")
            }
        }

        XCTAssertTrue(unfair.isEmpty,
                      "levels with a second arrangement no one can rule out:\n"
                      + unfair.joined(separator: "\n"))
    }

    /// Is every run in this arrangement an even walk, as a player judges it:
    /// interpolate between the run's two ends and require every interior cell
    /// to sit within a JND of where the interpolation puts it.
    ///
    /// Judged in OKLCh rather than OKLab, because that is where the ramps are
    /// authored and where the app's own solver says the walk lives — a pure
    /// hue step projects to a curved arc in a/b, so equal Lab deltas would be
    /// the wrong test.
    private func isEvenWalk(_ runs: [[CellIndex]], _ board: [CellIndex: OKLCh]) -> Bool {
        for path in runs where path.count >= 3 {
            let cols = path.map { board[$0]! }
            // Unwrap hue along the run so a ramp crossing 0° is not read as a
            // near-full rotation.
            var hues = [cols[0].h]
            for col in cols.dropFirst() {
                var h = col.h
                while h - hues[hues.count - 1] > 180 { h -= 360 }
                while h - hues[hues.count - 1] < -180 { h += 360 }
                hues.append(h)
            }
            let last = cols.count - 1
            for i in 1..<last {
                let f = Double(i) / Double(last)
                let want = OKLCh(L: cols[0].L + f * (cols[last].L - cols[0].L),
                                 c: cols[0].c + f * (cols[last].c - cols[0].c),
                                 h: hues[0] + f * (hues[last] - hues[0]))
                if !OK.equal(want, cols[i]) { return false }
            }
        }
        return true
    }

    /// How far the most unusual step on the board sits from the board's median
    /// step. The median authored level's fastest run steps only about 1.6× its
    /// slowest, so a run that suddenly jumps much further than everything else
    /// reads as wrong even though it is technically even.
    private func stepOddity(_ runs: [[CellIndex]], _ board: [CellIndex: OKLCh]) -> Double {
        var steps: [Double] = []
        for path in runs {
            for (a, b) in zip(path, path.dropFirst()) {
                steps.append(OK.dist(board[a]!, board[b]!))
            }
        }
        guard !steps.isEmpty else { return 0 }
        let sorted = steps.sorted()
        let mid = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        return steps.map { abs($0 - mid) }.max() ?? 0
    }

    /// Every run must be layable down, which is a different demand from the
    /// board having one solution.
    ///
    /// A player solves by sorting rather than matching: they group the swatches
    /// by run (the runs are built in different colour families), order each
    /// group along its ramp, then decide which way round it goes. That last
    /// step needs an anchor: a given cell on the run, or a cell shared with a
    /// run already placed, which inherits one. A run with neither is floating,
    /// and its direction is a coin flip no amount of colour separation can fix.
    /// The solver is happy with such a board because exhaustive search over
    /// exact colours rules the reversal out, but nobody plays that way.
    func testEveryRunCanBeOriented() throws {
        var floating: [String] = []

        for entry in CampaignCatalog.levels {
            guard let puzzle = entry.puzzle() else { continue }

            // Which coordinates are shared between two runs.
            var owners: [CellIndex: Set<Int>] = [:]
            for grad in puzzle.gradients {
                for spec in grad.cells {
                    owners[CellIndex(r: spec.r, c: spec.c), default: []].insert(grad.id)
                }
            }

            // Seed with the runs holding a given cell, then let orientation
            // spread through crossings.
            var oriented = Set(puzzle.gradients.filter { grad in
                grad.cells.contains { $0.locked }
            }.map { $0.id })
            var changed = true
            while changed {
                changed = false
                for grad in puzzle.gradients where !oriented.contains(grad.id) {
                    let touchesOriented = grad.cells.contains { spec in
                        (owners[CellIndex(r: spec.r, c: spec.c)] ?? []).contains {
                            $0 != grad.id && oriented.contains($0)
                        }
                    }
                    if touchesOriented {
                        oriented.insert(grad.id)
                        changed = true
                    }
                }
            }

            for grad in puzzle.gradients where !oriented.contains(grad.id) {
                floating.append("\(entry.index) \(entry.name): gradient \(grad.id) "
                                + "(\(grad.cells.count) cells) has no given cell and no "
                                + "crossing, so its direction is a guess")
            }
        }

        XCTAssertTrue(floating.isEmpty,
                      "runs a player cannot orient:\n" + floating.joined(separator: "\n"))
    }

    /// A board with nothing given and nothing deducible is a search problem,
    /// not a puzzle. Catch that shape of mistake with its own message, since
    /// the margin test above would report it as a pile of unrelated cells.
    func testNoLevelIsPureSearch() throws {
        for entry in CampaignCatalog.levels {
            guard let puzzle = entry.puzzle() else { continue }
            var given: Set<CellIndex> = []
            var freeCount = 0
            for grad in puzzle.gradients {
                for spec in grad.cells {
                    if spec.locked {
                        given.insert(CellIndex(r: spec.r, c: spec.c))
                    } else {
                        freeCount += 1
                    }
                }
            }
            guard freeCount > 1 else { continue }
            let deduced = deductionClosure(puzzle, given: given).count - given.count
            XCTAssertFalse(given.isEmpty && deduced == 0,
                           "level \(entry.index) (\(entry.name)) gives the player nothing to "
                           + "start from and nothing to deduce")
        }
    }
}
