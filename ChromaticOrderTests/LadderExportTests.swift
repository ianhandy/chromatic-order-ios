//  Data export for offline grading of the procedural difficulty ladder.
//
//  The generator is the only place that knows what a level 17 board
//  actually looks like, so the simulated-human grader can't be fed
//  hand-written fixtures, it has to read real generator output. This
//  test sweeps levels 1...21, serialises every puzzle through the same
//  codec the authored campaign uses (CreatorCodec / CreatorPuzzleDoc),
//  and drops one file the Python grader can point at for both sources.
//
//  It is an export, not an assertion suite, with one exception: the
//  round-trip check. If encode -> decode -> rebuild loses anything, the
//  grader is scoring a board no player will ever see, so that failure
//  has to surface here rather than as a mystery in the analysis.

import XCTest
@testable import ChromaticOrder

final class LadderExportTests: XCTestCase {

    // MARK: sweep parameters

    private static let levelRange = 1...21
    private static let samplesPerLevel = 40
    /// Fixed path: the Python grader looks here, and /tmp is shared with
    /// the host, so the name has to stay exactly this.
    private static let outputPath = "/tmp/kroma-ladder-export.json"
    /// Puzzles per level kept aside for the faithfulness check. Two per
    /// level clears the 20-sample floor with room to spare and spreads
    /// the check across the whole ladder instead of clustering it at
    /// the easy end, where boards are small enough to hide bugs.
    private static let roundTripSamplesPerLevel = 2

    // MARK: export schema
    //
    // Mirrors CampaignLevel's envelope (index / name / chapter / doc) so
    // the grader has one reader for authored and generated ladders. The
    // extra `level` field is what an authored campaign has no analogue
    // for: which difficulty tier this board was requested at.

    private struct ExportEntry: Encodable {
        let index: Int
        let name: String
        let chapter: String
        let level: Int
        let bankCount: Int
        let doc: CreatorPuzzleDoc
    }

    /// mean / sd / min / max of one measurement across a level's samples.
    /// Rounded on the way out because these are reading aids for a human
    /// scanning the ladder, not inputs to further colour math (the
    /// per-cell values in `doc` keep full precision).
    private struct Summary: Encodable {
        let mean: Double
        let sd: Double
        let min: Double
        let max: Double

        init(_ xs: [Double]) {
            guard !xs.isEmpty else {
                mean = 0; sd = 0; min = 0; max = 0
                return
            }
            let m = xs.reduce(0, +) / Double(xs.count)
            // Population sd: we have the whole sample set for the level
            // and are describing it, not inferring a wider population.
            let variance = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)
            func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
            mean = round4(m)
            sd = round4(variance.squareRoot())
            min = round4(xs.min() ?? 0)
            max = round4(xs.max() ?? 0)
        }
    }

    private struct LevelStats: Encodable {
        let level: Int
        let puzzles: Int
        let cellCount: Summary
        let bankCount: Summary
        let gradientCount: Summary
        /// Smallest ΔE between any two distinct cells on the board. This
        /// is the discriminability number: if it drops under ~2 the two
        /// cells are the same colour to a human, and the level stops
        /// being a puzzle and starts being a coin flip.
        let minPairDeltaE: Summary
    }

    private struct ExportFile: Encodable {
        let levels: [ExportEntry]
        let stats: [String: LevelStats]
    }

    // MARK: board readers

    /// One entry per distinct grid position, read off the board rather
    /// than off the gradients. Intersection cells appear in two
    /// gradients' `cells` arrays, so anything derived from gradients
    /// double counts them; the board already holds the merged truth
    /// (including the merged lock state).
    private struct BoardCellRead {
        let r: Int
        let c: Int
        let color: OKLCh
        let locked: Bool
    }

    private func distinctCells(_ p: Puzzle) -> [BoardCellRead] {
        var out: [BoardCellRead] = []
        for r in 0..<p.gridH {
            for c in 0..<p.gridW {
                let cell = p.board[r][c]
                guard cell.kind == .cell, let solution = cell.solution else { continue }
                out.append(BoardCellRead(r: r, c: c, color: solution, locked: cell.locked))
            }
        }
        return out
    }

    /// Positions whose lock flag disagrees between the gradients that
    /// share them. An intersection cell is stored once per gradient, and
    /// some of the uniqueness guards set `locked` on a single gradient's
    /// copy, so the two consumers of that data disagree: the board ORs
    /// the flags (cell is locked) while the bank builder banks the
    /// position on the first unlocked copy it meets (cell is free).
    /// Naming the position is what makes such a board debuggable.
    private func conflictingLockPositions(_ p: Puzzle) -> [String] {
        var flagsByPosition: [String: Set<Bool>] = [:]
        for g in p.gradients {
            for spec in g.cells {
                flagsByPosition["\(spec.r),\(spec.c)", default: []].insert(spec.locked)
            }
        }
        return flagsByPosition.filter { $0.value.count > 1 }.keys.sorted()
    }

    /// Every unordered pair of distinct cells, no shortcuts. A per
    /// gradient or nearest-neighbour scan would miss the case that
    /// actually hurts a player: two cells on different gradients,
    /// nowhere near each other on the grid, that look identical.
    private func minPairDeltaE(_ cells: [BoardCellRead]) -> Double {
        guard cells.count >= 2 else { return .infinity }
        var best = Double.infinity
        for i in 0..<(cells.count - 1) {
            for j in (i + 1)..<cells.count {
                let d = OK.dist(cells[i].color, cells[j].color)
                if d < best { best = d }
            }
        }
        return best
    }

    // MARK: the export

    func testExportLadderForOfflineGrading() throws {
        // 840 generations, and the top levels spend real time in the
        // builder's retry loops. Ask for a generous allowance so a slow
        // machine reports numbers instead of a timeout.
        executionTimeAllowance = 3_600

        var entries: [ExportEntry] = []
        var stats: [String: LevelStats] = [:]
        var tableRows: [String] = []
        // Kept aside for the faithfulness check: the live Puzzle next to
        // the index of the entry it produced, so a failure can name the
        // exact export row that is wrong.
        var roundTripSamples: [(entryIndex: Int, puzzle: Puzzle)] = []
        // Boards where the generator's own bank does not match the empty
        // cells on its board. Collected rather than asserted: this is
        // pre-existing generator behaviour, and the export's job is to
        // report it accurately, not to block on it.
        var bankMismatches: [String] = []

        let sweepStart = Date()

        for level in Self.levelRange {
            let levelStart = Date()
            var cellCounts: [Double] = []
            var bankCounts: [Double] = []
            var gradientCounts: [Double] = []
            var minDeltas: [Double] = []

            for n in 1...Self.samplesPerLevel {
                // GenConfig() defaults on purpose: the stash / recent /
                // seen-today ledgers are part of what a player gets, and
                // `deterministic` would switch all of that off, grading
                // a generator nobody plays.
                let puzzle = generatePuzzle(level: level)
                let cells = distinctCells(puzzle)
                let freeCells = cells.filter { !$0.locked }.count

                // `bankCount` in the export is the free-cell count, since
                // "cells the player has to fill" is the quantity the
                // grader models. The generator's own bank should agree.
                // When it does not, the board carries a spare swatch, and
                // the grader needs to know these boards exist (a
                // simulated human that runs out of cells with a swatch
                // still in hand is not stuck, it is finished).
                if freeCells != puzzle.initialBankCount {
                    let conflicts = conflictingLockPositions(puzzle)
                    bankMismatches.append(
                        "lv\(level)-\(n) (entry \(entries.count + 1)): board has \(freeCells) "
                        + "free cells but the bank holds \(puzzle.initialBankCount); "
                        + "cells locked in one gradient and free in another: \(conflicts)")
                }

                let json = try CreatorCodec.encodePuzzle(puzzle)
                let doc = try CreatorCodec.decode(Data(json.utf8))

                let index = entries.count + 1
                entries.append(ExportEntry(
                    index: index,
                    name: "lv\(level)-\(n)",
                    chapter: "level \(level)",
                    level: level,
                    bankCount: freeCells,
                    doc: doc))

                // Always round-trip a board with a lock disagreement: it
                // is the shape most likely to survive encode but not
                // rebuild, since the two carry that merge separately.
                if n <= Self.roundTripSamplesPerLevel || freeCells != puzzle.initialBankCount {
                    roundTripSamples.append((entryIndex: index, puzzle: puzzle))
                }

                cellCounts.append(Double(cells.count))
                bankCounts.append(Double(freeCells))
                gradientCounts.append(Double(puzzle.gradients.count))
                minDeltas.append(minPairDeltaE(cells))
            }

            let levelStats = LevelStats(
                level: level,
                puzzles: Self.samplesPerLevel,
                cellCount: Summary(cellCounts),
                bankCount: Summary(bankCounts),
                gradientCount: Summary(gradientCounts),
                minPairDeltaE: Summary(minDeltas))
            stats["\(level)"] = levelStats

            let row = String(
                format: "%5d  %6.1f %5.1f  %6.1f %5.1f  %5.1f %5.1f  %7.2f %6.2f %7.2f",
                level,
                levelStats.cellCount.mean, levelStats.cellCount.sd,
                levelStats.bankCount.mean, levelStats.bankCount.sd,
                levelStats.gradientCount.mean, levelStats.gradientCount.sd,
                levelStats.minPairDeltaE.mean, levelStats.minPairDeltaE.sd,
                levelStats.minPairDeltaE.min)
            tableRows.append(row)

            // Per-level progress: 840 generations with no output looks
            // exactly like a hang.
            print(String(format: "[LadderExport] level %2d done, %d puzzles in %.1fs "
                                 + "(cells %.1f, bank %.1f, grads %.1f, minΔE mean %.2f worst %.2f)",
                         level, Self.samplesPerLevel, Date().timeIntervalSince(levelStart),
                         levelStats.cellCount.mean, levelStats.bankCount.mean,
                         levelStats.gradientCount.mean,
                         levelStats.minPairDeltaE.mean, levelStats.minPairDeltaE.min))
            fflush(stdout)
        }

        // MARK: faithfulness

        var drift: [String] = []
        for sample in roundTripSamples {
            let original = sample.puzzle
            let json = try CreatorCodec.encodePuzzle(original)
            let doc = try CreatorCodec.decode(Data(json.utf8))
            guard let rebuilt = CreatorCodec.rebuild(doc, level: original.level) else {
                drift.append("entry \(sample.entryIndex): rebuild returned nil")
                continue
            }

            if rebuilt.gridW != original.gridW || rebuilt.gridH != original.gridH {
                drift.append("entry \(sample.entryIndex): grid \(original.gridW)x\(original.gridH) "
                             + "became \(rebuilt.gridW)x\(rebuilt.gridH)")
            }
            // Bank size travels too: it is derived from the same lock
            // flags, so a rebuild that banks a different number of
            // swatches means the doc lost a lock somewhere.
            if rebuilt.initialBankCount != original.initialBankCount {
                drift.append("entry \(sample.entryIndex): bank \(original.initialBankCount) "
                             + "became \(rebuilt.initialBankCount)")
            }
            if rebuilt.gradients.count != original.gradients.count {
                drift.append("entry \(sample.entryIndex): \(original.gradients.count) gradients "
                             + "became \(rebuilt.gradients.count)")
            }

            let originalCells = distinctCells(original)
            let rebuiltCells = distinctCells(rebuilt)
            let originalLocks = Set(originalCells.filter { $0.locked }.map { [$0.r, $0.c] })
            let rebuiltLocks = Set(rebuiltCells.filter { $0.locked }.map { [$0.r, $0.c] })
            if originalLocks != rebuiltLocks {
                let lost = originalLocks.subtracting(rebuiltLocks).sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
                let gained = rebuiltLocks.subtracting(originalLocks).sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
                drift.append("entry \(sample.entryIndex): locks lost \(lost) gained \(gained)")
            }

            // Colours compared by grid position, since cell ordering is
            // the codec's business and position is what the player sees.
            var rebuiltByPos: [String: OKLCh] = [:]
            for cell in rebuiltCells { rebuiltByPos["\(cell.r),\(cell.c)"] = cell.color }
            if originalCells.count != rebuiltCells.count {
                drift.append("entry \(sample.entryIndex): \(originalCells.count) cells "
                             + "became \(rebuiltCells.count)")
            }
            for cell in originalCells {
                guard let after = rebuiltByPos["\(cell.r),\(cell.c)"] else {
                    drift.append("entry \(sample.entryIndex): cell \(cell.r),\(cell.c) missing "
                                 + "after rebuild")
                    continue
                }
                let d = OK.dist(cell.color, after)
                if d > 0.01 {
                    drift.append(String(format: "entry %d: cell %d,%d drifted ΔE %.6f "
                                        + "(L %.6f c %.6f h %.6f -> L %.6f c %.6f h %.6f)",
                                        sample.entryIndex, cell.r, cell.c, d,
                                        cell.color.L, cell.color.c, cell.color.h,
                                        after.L, after.c, after.h))
                }
            }
        }

        XCTAssertTrue(drift.isEmpty,
                      "round trip is lossy across \(roundTripSamples.count) sampled puzzles:\n"
                      + drift.prefix(40).joined(separator: "\n"))

        // MARK: write

        let encoder = JSONEncoder()
        // Sorted keys so a diff between two exports is readable.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ExportFile(levels: entries, stats: stats))
        let url = URL(fileURLWithPath: Self.outputPath)
        try data.write(to: url)

        let header = "level  cells    sd    bank    sd  grads    sd    minΔE    sd    worst"
        print("\n[LadderExport] per-level statistics (mean and sd over "
              + "\(Self.samplesPerLevel) puzzles)")
        print(header)
        for row in tableRows { print(row) }

        if bankMismatches.isEmpty {
            print("\n[LadderExport] bank size matched the free cells on all "
                  + "\(entries.count) boards")
        } else {
            print("\n[LadderExport] GENERATOR QUIRK: \(bankMismatches.count) of "
                  + "\(entries.count) boards ship a bank that does not match their free "
                  + "cells. bankCount in the export is the free-cell count, which is what "
                  + "the player must fill. Affected boards:")
            for line in bankMismatches { print("  " + line) }
        }

        print("\n[LadderExport] wrote \(Self.outputPath)")
        print(String(format: "[LadderExport] levels %d...%d, %d puzzles, %d bytes, "
                             + "round trip verified on %d puzzles, swept in %.1fs",
                     Self.levelRange.lowerBound, Self.levelRange.upperBound,
                     entries.count, data.count, roundTripSamples.count,
                     Date().timeIntervalSince(sweepStart)))
        fflush(stdout)

        XCTAssertEqual(entries.count,
                       Self.levelRange.count * Self.samplesPerLevel,
                       "export should hold every generated puzzle")
        XCTAssertEqual(Set(entries.map { $0.index }).count, entries.count,
                       "index must be unique across the file")
    }
}
