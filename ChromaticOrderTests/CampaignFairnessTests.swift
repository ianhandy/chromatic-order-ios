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

        // Sanity only: the report is worthless if it silently measured nothing.
        XCTAssertEqual(stats.count, CampaignCatalog.count)
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
