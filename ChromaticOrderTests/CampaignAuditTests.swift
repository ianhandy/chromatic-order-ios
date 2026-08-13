//  Audit of the shipped intro campaign. The levels are authored offline by
//  tools/campaign/, which validates them against a Python port of the
//  solver — this file is the ground-truth check against the real Swift
//  code, so a regenerated campaign.json can't ship a board that is
//  ambiguous, off-palette, or too big for the phone.

import XCTest
@testable import ChromaticOrder

final class CampaignAuditTests: XCTestCase {

    /// The bundle under test is the host app's, so the resource lookup here
    /// exercises exactly the path CampaignCatalog uses at runtime.
    func testCampaignLoads() throws {
        XCTAssertEqual(CampaignCatalog.count, 100,
                       "campaign.json should carry 100 levels")
        XCTAssertEqual(CampaignCatalog.chapters.count, 7)
        // Chapters must tile 1...100 with no gaps or overlaps, since the
        // picker groups every level under exactly one of them.
        var expected = 1
        for chapter in CampaignCatalog.chapters {
            XCTAssertEqual(chapter.first, expected,
                           "chapter \(chapter.title) starts at \(chapter.first)")
            XCTAssertGreaterThanOrEqual(chapter.last, chapter.first)
            expected = chapter.last + 1
        }
        XCTAssertEqual(expected, 101, "chapters should cover through level 100")

        for (offset, level) in CampaignCatalog.levels.enumerated() {
            XCTAssertEqual(level.index, offset + 1, "levels must be in order")
            XCTAssertFalse(level.name.isEmpty)
            XCTAssertLessThanOrEqual(level.name.split(separator: " ").count, 2,
                                     "\(level.name) should be one or two words")
            XCTAssertNotNil(CampaignCatalog.chapter(containing: level.index))
        }
    }

    /// Every level: rebuilds, fits the phone, keeps its colours inside the
    /// usable band, leaves each gradient something to solve, and has
    /// exactly one placement a player can arrive at.
    func testEveryCampaignLevelIsPlayableAndUnique() throws {
        var report = "level  name          grid   grads  cells  bank  minΔE  locks\n"
        var ambiguous: [String] = []

        for entry in CampaignCatalog.levels {
            guard let puzzle = entry.puzzle() else {
                XCTFail("level \(entry.index) (\(entry.name)) failed to rebuild")
                continue
            }

            XCTAssertLessThanOrEqual(puzzle.gridW, 11,
                                     "level \(entry.index) is \(puzzle.gridW) wide")
            XCTAssertLessThanOrEqual(puzzle.gridH, 9,
                                     "level \(entry.index) is \(puzzle.gridH) tall")

            // Colours: inside the palette band the renderer is tuned for.
            for grad in puzzle.gradients {
                for spec in grad.cells {
                    XCTAssertTrue(OK.inUsableBand(spec.color),
                                  "level \(entry.index) cell \(spec.r),\(spec.c) "
                                  + "outside the usable band")
                }
                // Every gradient needs at least one cell to place, or the
                // player can't finish it.
                XCTAssertTrue(grad.cells.contains { !$0.locked },
                              "level \(entry.index) gradient \(grad.id) is fully locked")
                // Two cells with the same colour inside one gradient would
                // make its order unreadable.
                for i in 0..<grad.colors.count {
                    for j in (i + 1)..<grad.colors.count {
                        XCTAssertGreaterThanOrEqual(
                            OK.dist(grad.colors[i], grad.colors[j]), 2.0,
                            "level \(entry.index) gradient \(grad.id) repeats a colour")
                    }
                }
            }

            // Shared cells must agree: an intersection carries one colour.
            var byCell: [CellIndex: OKLCh] = [:]
            for grad in puzzle.gradients {
                for spec in grad.cells {
                    let key = CellIndex(r: spec.r, c: spec.c)
                    if let seen = byCell[key] {
                        XCTAssertLessThan(
                            OK.dist(seen, spec.color), 1.0,
                            "level \(entry.index) crossing \(spec.r),\(spec.c) disagrees")
                    } else {
                        byCell[key] = spec.color
                    }
                }
            }

            // The bank has to hold exactly the free cells.
            let freeCount = byCell.keys.filter { key in
                !(puzzle.board[key.r][key.c].locked)
            }.count
            XCTAssertEqual(puzzle.bank.compactMap { $0 }.count, freeCount,
                           "level \(entry.index) bank size disagrees with free cells")
            XCTAssertEqual(entry.bankCount, freeCount,
                           "level \(entry.index) metadata bank count is stale")
            XCTAssertEqual(entry.cellCount, byCell.count,
                           "level \(entry.index) metadata cell count is stale")
            XCTAssertEqual(entry.gradientCount, puzzle.gradients.count,
                           "level \(entry.index) metadata gradient count is stale")

            // The real solver, same rules the generator's own audit uses.
            if !PuzzleSolver.isUniquelySolvable(puzzle) {
                let count = PuzzleSolver.countValidPlacements(puzzle, limit: 3)
                ambiguous.append("\(entry.index) \(entry.name): \(count) placements")
            }

            let colors = Array(byCell.values)
            var minPair = Double.greatestFiniteMagnitude
            for i in 0..<colors.count {
                for j in (i + 1)..<colors.count {
                    minPair = min(minPair, OK.dist(colors[i], colors[j]))
                }
            }
            let locks = byCell.keys.filter { puzzle.board[$0.r][$0.c].locked }.count
            let paddedName = entry.name.padding(toLength: 13, withPad: " ",
                                                startingAt: 0)
            let de = minPair == .greatestFiniteMagnitude ? 0 : minPair
            report += "\(String(format: "%5d", entry.index))  \(paddedName)"
                + "\(puzzle.gridW)x\(puzzle.gridH)   \(puzzle.gradients.count)     "
                + "\(byCell.count)     \(freeCount)    "
                + "\(String(format: "%5.1f", de))   \(locks)\n"
        }

        let path = "/tmp/kroma-campaign-audit.txt"
        try? report.write(toFile: path, atomically: true, encoding: .utf8)
        print("[CampaignAudit] wrote \(path)")

        XCTAssertTrue(ambiguous.isEmpty,
                      "campaign levels with more than one solution:\n"
                      + ambiguous.joined(separator: "\n"))
    }

    /// The campaign is a ramp: boards and banks should grow, not lurch.
    ///
    /// Swatch count is deliberately NOT held to a tight neighbour-to-neighbour
    /// limit any more. It used to be the difficulty knob, but the fairness pass
    /// in tools/campaign/build.py now overrides it per shape: a run with no
    /// given cell and no crossing cannot be oriented by a player, so it gets a
    /// given cell, and a small board full of short runs (Ant, 14 cells) needs
    /// proportionally more of them than a big open one. That is the board being
    /// made playable, not the pacing wobbling, so the ramp is checked on a
    /// three-level average and on the authored quantity, board size, instead.
    func testDifficultyRampIsMonotonicEnough() throws {
        let banks = CampaignCatalog.levels.map { $0.bankCount }
        let cells = CampaignCatalog.levels.map { $0.cellCount }
        XCTAssertEqual(banks.first, 1, "level 1 should ask for a single swatch")
        XCTAssertGreaterThan(banks.last ?? 0, 20, "the finale should be a full board")

        // Every board must give the player something to do, and never more
        // swatches than there are cells to put them in.
        for (i, entry) in CampaignCatalog.levels.enumerated() {
            XCTAssertGreaterThan(banks[i], 0, "level \(entry.index) has nothing to place")
            XCTAssertLessThanOrEqual(banks[i], cells[i],
                                     "level \(entry.index) has more swatches than cells")
        }

        // Smoothed, the swatch count must not leap: a three-level window
        // absorbs per-shape anchor costs while still catching a real cliff.
        func window(_ values: [Int], _ i: Int) -> Double {
            let lo = max(0, i - 1), hi = min(values.count - 1, i + 1)
            return Double(values[lo...hi].reduce(0, +)) / Double(hi - lo + 1)
        }
        for i in 1..<banks.count {
            XCTAssertLessThanOrEqual(window(banks, i) - window(banks, i - 1), 6.0,
                                     "level \(i + 1) leaps in swatch count even smoothed")
        }

        // Averaged over a chapter, the trend must be upward.
        var previousAverage = 0.0
        for chapter in CampaignCatalog.chapters {
            let levels = CampaignCatalog.levels(in: chapter)
            let average = Double(levels.reduce(0) { $0 + $1.bankCount }) / Double(levels.count)
            XCTAssertGreaterThan(average, previousAverage,
                                 "chapter \(chapter.title) doesn't step up")
            previousAverage = average
        }
    }

    /// The session wiring: loading a level tags the session, solving it
    /// records the clear and moves to the next authored level (rather than
    /// rerolling a generated zen board), skip re-serves the same level, and
    /// the finale ends the run instead of walking off the end.
    @MainActor
    func testCampaignSessionAdvancesThroughAuthoredLevels() throws {
        CampaignStore.resetAll()
        let game = GameState()

        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertEqual(game.campaignIndex, 1)
        XCTAssertEqual(game.customTitle, CampaignCatalog.level(1)?.name)
        XCTAssertNotNil(game.puzzle)
        XCTAssertFalse(game.generating, "authored levels don't wait on the generator")
        XCTAssertNotNil(game.campaignTip, "level 1 introduces the drag")

        // Skip stays on the same level — there is no alternate board.
        game.handleSkip()
        XCTAssertEqual(game.campaignIndex, 1)

        // Solve → next level, and the clear is recorded.
        game.handleNext()
        XCTAssertEqual(game.campaignIndex, 2)
        XCTAssertTrue(CampaignStore.isCleared(1))
        XCTAssertEqual(game.customTitle, CampaignCatalog.level(2)?.name)
        XCTAssertFalse(game.campaignComplete)

        // A tip only ever shows once.
        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertNil(game.campaignTip)

        // The finale ends the campaign rather than advancing past 100.
        XCTAssertTrue(game.loadCampaignLevel(CampaignCatalog.count))
        game.handleNext()
        XCTAssertTrue(game.campaignComplete)
        XCTAssertTrue(CampaignStore.isCleared(CampaignCatalog.count))

        // Leaving for a generated board clears the campaign tag, so campaign
        // rules stop applying to it.
        game.enterMode(.zen)
        XCTAssertNil(game.campaignIndex)
        CampaignStore.resetAll()
    }

    /// End-to-end: load every level, place every swatch through the same
    /// API the drag gesture uses, and check it. This is the test that would
    /// catch a level whose bank doesn't match its board, an intersection
    /// counted twice, or a colour the check rejects — things a solver-only
    /// audit can't see.
    @MainActor
    func testEveryCampaignLevelPlaysToASolve() throws {
        CampaignStore.resetAll()
        let game = GameState()
        var failures: [String] = []

        for entry in CampaignCatalog.levels {
            guard game.loadCampaignLevel(entry.index), let puzzle = game.puzzle else {
                failures.append("\(entry.index) \(entry.name): would not load")
                continue
            }

            // Every free cell, and the colour it wants.
            var wanted: [(r: Int, c: Int, color: OKLCh)] = []
            for r in 0..<puzzle.gridH {
                for c in 0..<puzzle.gridW {
                    let cell = puzzle.board[r][c]
                    guard cell.kind == .cell, !cell.locked,
                          let solution = cell.solution else { continue }
                    wanted.append((r, c, solution))
                }
            }
            if wanted.count != entry.bankCount {
                failures.append("\(entry.index) \(entry.name): \(wanted.count) free cells "
                                + "vs bank metadata \(entry.bankCount)")
            }

            for target in wanted {
                let slot = game.puzzle?.bank.firstIndex { item in
                    guard let item else { return false }
                    return OK.equal(item.color, target.color)
                }
                guard let slot else {
                    failures.append("\(entry.index) \(entry.name): no swatch matches "
                                    + "cell \(target.r),\(target.c)")
                    break
                }
                game.placeSlotIntoCell(slot, at: target.r, target.c)
            }

            let leftover = game.puzzle?.bank.compactMap { $0 }.count ?? -1
            if leftover != 0 {
                failures.append("\(entry.index) \(entry.name): \(leftover) swatches "
                                + "left in the bank after filling every cell")
            }

            game.handleCheck()
            if !game.solved {
                failures.append("\(entry.index) \(entry.name): check rejected the solution")
            }
        }

        CampaignStore.resetAll()
        XCTAssertTrue(failures.isEmpty,
                      "levels that don't play cleanly:\n" + failures.joined(separator: "\n"))
    }

    /// A campaign level loaded while the generator is still working on a
    /// board must survive: generation runs detached, and its result used to
    /// land on top of the authored puzzle a beat later — which is exactly
    /// what happens on first launch, when the app opens onto campaign
    /// level 1 while GameState's own startLevel is still in flight.
    @MainActor
    func testCampaignLevelSurvivesAnInFlightGeneration() async throws {
        CampaignStore.resetAll()
        let game = GameState()
        game.startLevel(1)                    // detached generation begins
        XCTAssertTrue(game.loadCampaignLevel(1))
        let expected = try XCTUnwrap(CampaignCatalog.level(1))

        // Give the generator time to finish and try to publish.
        try await Task.sleep(for: .seconds(2))

        XCTAssertEqual(game.campaignIndex, 1, "campaign tag was cleared")
        XCTAssertEqual(game.customTitle, expected.name)
        let puzzle = try XCTUnwrap(game.puzzle)
        XCTAssertEqual(puzzle.gridW, expected.doc.gridW,
                       "a generated board replaced the campaign level")
        XCTAssertEqual(puzzle.gridH, expected.doc.gridH)
        XCTAssertEqual(puzzle.bank.compactMap { $0 }.count, expected.bankCount)
        XCTAssertFalse(game.generating)
        CampaignStore.resetAll()
    }

    /// A tip that describes the board is a claim about it. The authoring tool
    /// enforces these at build time (see TIP_CLAIMS in tools/campaign), and
    /// this re-checks the shipped JSON from the app's side by reading the tip
    /// text itself — so an edited tip that no longer matches its level fails
    /// here rather than confusing a player.
    func testTipsDescribeTheirOwnLevel() throws {
        var problems: [String] = []

        for entry in CampaignCatalog.levels {
            guard let tip = entry.tip?.lowercased(), !tip.isEmpty else { continue }
            guard let puzzle = entry.puzzle() else { continue }

            var byCell: [CellIndex: [Int]] = [:]
            for grad in puzzle.gradients {
                for spec in grad.cells {
                    byCell[CellIndex(r: spec.r, c: spec.c), default: []].append(grad.id)
                }
            }
            let shared = byCell.filter { $0.value.count >= 2 }
            let free = byCell.keys.filter { !puzzle.board[$0.r][$0.c].locked }
            let endpointsGiven = puzzle.gradients.allSatisfy { grad in
                guard let first = grad.cells.min(by: { $0.pos < $1.pos }),
                      let last = grad.cells.max(by: { $0.pos < $1.pos }) else { return false }
                return first.locked && last.locked
            }

            func check(_ condition: Bool, _ why: String) {
                if !condition {
                    problems.append("\(entry.index) \(entry.name): \(why) — tip: \"\(entry.tip ?? "")\"")
                }
            }

            // "both ends are already placed" / "the ends are given" / "trust the ends"
            if tip.contains("both ends") || tip.contains("the ends are given")
                || tip.contains("trust the ends") {
                check(endpointsGiven, "claims the ends are given, but some gradient's endpoint is free")
            }
            // A tip that says one swatch had better mean one swatch.
            if tip.contains("the swatch into the empty cell") {
                check(free.count == 1, "claims a single empty cell, but \(free.count) are free")
            }
            // Anything about sharing / meeting / crossings needs a shared cell.
            if tip.contains("shared") || tip.contains("belongs to both")
                || tip.contains("crossing") || tip.contains("where the two strokes meet")
                || tip.contains("shares an end") {
                check(!shared.isEmpty, "talks about shared cells, but the level has none")
            }
            // ...and a tip that says nothing crosses had better have nothing crossing.
            if tip.contains("nothing crosses") || tip.contains("ramps on its own") {
                check(shared.isEmpty, "says nothing crosses, but the level has \(shared.count) shared cells")
            }
            // "every stroke shares an end" / "each one hands the next"
            if tip.contains("every stroke shares an end") || tip.contains("hands the next") {
                let allTouch = puzzle.gradients.allSatisfy { grad in
                    grad.cells.contains { shared[CellIndex(r: $0.r, c: $0.c)] != nil }
                }
                check(allTouch, "claims every stroke is crossed, but one isn't")
            }
            // Chroma talk needs a gradient whose chroma moves at a fixed hue.
            if tip.contains("chroma") || tip.contains("draining colour") {
                let hasChromaRamp = puzzle.gradients.contains { grad in
                    guard grad.colors.count >= 2 else { return false }
                    let a = grad.colors[0], b = grad.colors[1]
                    var dh = abs(a.h - b.h)
                    if dh > 180 { dh = 360 - dh }
                    return abs(a.c - b.c) > 0.008 && dh < 2
                }
                check(hasChromaRamp, "promises a chroma ramp, but no gradient ramps chroma")
            }
            // Colour-family talk needs the families to actually be apart.
            if tip.contains("colour families") || tip.contains("families") {
                var means: [Double] = []
                for grad in puzzle.gradients {
                    let x = grad.colors.reduce(0.0) { $0 + cos($1.h * .pi / 180) }
                    let y = grad.colors.reduce(0.0) { $0 + sin($1.h * .pi / 180) }
                    means.append(atan2(y, x) * 180 / .pi)
                }
                var closest = 360.0
                for i in 0..<means.count {
                    for j in (i + 1)..<means.count {
                        var d = abs(means[i] - means[j]).truncatingRemainder(dividingBy: 360)
                        if d > 180 { d = 360 - d }
                        closest = min(closest, d)
                    }
                }
                check(closest >= 40,
                      "claims different colour families, but two are only "
                      + String(format: "%.0f", closest) + "° apart")
            }
            // Counting words in a tip are a trap — the bank size comes from the
            // difficulty curve, so a rebuild can silently invalidate them.
            for word in ["two to place", "three to place", "three in a row",
                         "four to place"] {
                check(!tip.contains(word),
                      "hard-codes a swatch count (\"\(word)\"); the curve owns that number")
            }
            // The board is never annotated, so no tip may point at a marking.
            check(!tip.contains("marked cell"),
                  "says \"marked cell\", but shared cells render like any other")
        }

        XCTAssertTrue(problems.isEmpty,
                      "tips that don't match their level:\n"
                      + problems.joined(separator: "\n"))
    }

    /// The tips read as a sequence — "two gradients now", "chroma ramps now
    /// too" — so a mechanic must not turn up before the tip that names it.
    /// Chroma appearing in chapter 4 while its tip sits at level 53 would
    /// teach the campaign out of order.
    func testMechanicsArriveWithTheTipThatIntroducesThem() throws {
        func firstLevel(where predicate: (CampaignLevel) -> Bool) -> Int? {
            CampaignCatalog.levels.first(where: predicate)?.index
        }
        func tipMentions(_ entry: CampaignLevel, _ word: String) -> Bool {
            entry.tip?.lowercased().contains(word) ?? false
        }

        let hasChromaRamp: (CampaignLevel) -> Bool = { entry in
            entry.doc.gradients.contains { grad in
                guard grad.cells.count >= 2 else { return false }
                let a = grad.cells[0], b = grad.cells[1]
                var dh = abs(a.h - b.h).truncatingRemainder(dividingBy: 360)
                if dh > 180 { dh = 360 - dh }
                return abs(a.C - b.C) > 0.008 && dh < 2
            }
        }
        let hasSecondGradient: (CampaignLevel) -> Bool = { $0.doc.gradients.count >= 2 }
        let hasSharedCell: (CampaignLevel) -> Bool = { entry in
            var seen: Set<String> = []
            for grad in entry.doc.gradients {
                for cell in grad.cells {
                    if !seen.insert("\(cell.r),\(cell.c)").inserted { return true }
                }
            }
            return false
        }

        for (probe, word, label) in [
            (hasChromaRamp, "chroma", "a chroma ramp"),
            (hasSecondGradient, "two gradients", "a second gradient"),
            (hasSharedCell, "belongs to both", "a shared cell"),
        ] {
            guard let introduced = firstLevel(where: { tipMentions($0, word) }),
                  let appears = firstLevel(where: probe) else { continue }
            XCTAssertEqual(appears, introduced,
                           "\(label) first appears on level \(appears) but its tip "
                           + "is on level \(introduced)")
        }
    }

    /// Unlocking is strictly sequential, and replay stays open.
    func testProgressGating() throws {
        CampaignStore.resetAll()
        XCTAssertTrue(CampaignStore.isUnlocked(1))
        XCTAssertFalse(CampaignStore.isUnlocked(2))
        XCTAssertEqual(CampaignStore.nextUp, 1)

        CampaignStore.markCleared(1)
        XCTAssertTrue(CampaignStore.isUnlocked(1), "cleared levels stay replayable")
        XCTAssertTrue(CampaignStore.isUnlocked(2))
        XCTAssertFalse(CampaignStore.isUnlocked(3))
        XCTAssertEqual(CampaignStore.nextUp, 2)
        XCTAssertFalse(CampaignStore.isComplete)
        CampaignStore.resetAll()
    }
}
