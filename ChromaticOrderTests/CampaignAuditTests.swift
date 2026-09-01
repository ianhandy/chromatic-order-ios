//  Audit of the shipped intro campaign. The levels are authored offline by
//  tools/campaign/, which validates them against a Python port of the
//  solver — this file is the ground-truth check against the real Swift
//  code, so a regenerated campaign.json can't ship a board that is
//  ambiguous, off-palette, or too big for the phone.

import XCTest
@testable import ChromaticOrder

final class CampaignAuditTests: XCTestCase {

    private func source(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repository.appendingPathComponent(relativePath),
                          encoding: .utf8)
    }

    /// The bundle under test is the host app's, so the resource lookup here
    /// exercises exactly the path CampaignCatalog uses at runtime.
    func testCampaignLoads() throws {
        // Deliberately not a hardcoded total. The campaign has grown
        // twice — 100, then 200, then the red-herring chapter — and each
        // time the literal here was the only thing that broke. What
        // actually has to hold is that the chapters tile the levels
        // exactly, which the loop below checks.
        XCTAssertGreaterThan(CampaignCatalog.count, 0)
        XCTAssertFalse(CampaignCatalog.chapters.isEmpty)
        // Chapters must tile the campaign with no gaps or overlaps, since the
        // picker groups every level under exactly one of them.
        var expected = 1
        for chapter in CampaignCatalog.chapters {
            XCTAssertEqual(chapter.first, expected,
                           "chapter \(chapter.title) starts at \(chapter.first)")
            XCTAssertGreaterThanOrEqual(chapter.last, chapter.first)
            expected = chapter.last + 1
        }
        XCTAssertEqual(expected, CampaignCatalog.count + 1,
                       "chapters should cover every level, with no gaps or overlaps")

        for (offset, level) in CampaignCatalog.levels.enumerated() {
            XCTAssertEqual(level.index, offset + 1, "levels must be in order")
            XCTAssertFalse(level.name.isEmpty)
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

            // Book 1 fit inside 11x9. Book 2 does not and never did —
            // its late chapters need the room, and the grid scales to
            // fit with pinch-zoom past that. The cap that still matters
            // is the generator's own `GenConfig.maxGridSpan`, so match
            // it rather than keeping a stricter number the shipped
            // content has been failing since Book 2 landed.
            XCTAssertLessThanOrEqual(puzzle.gridW, 17,
                                     "level \(entry.index) is \(puzzle.gridW) wide")
            XCTAssertLessThanOrEqual(puzzle.gridH, 17,
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

            // The bank holds one swatch per free cell, plus this level's
            // red herrings — which belong in no cell by construction, so
            // they are surplus on purpose.
            let freeCount = byCell.keys.filter { key in
                !(puzzle.board[key.r][key.c].locked)
            }.count
            XCTAssertEqual(puzzle.bank.compactMap { $0 }.count,
                           freeCount + puzzle.decoys.count,
                           "level \(entry.index) bank size disagrees with free cells "
                           + "plus \(puzzle.decoys.count) decoys")
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

        // Averaged over a chapter, the trend must be upward within a book,
        // except when a chapter deliberately resets the geometry to teach a
        // new source of difficulty. Spare Parts uses smaller, clearer boards
        // because the surplus swatches carry the load; Sections and The Limit
        // then combine that mechanic with larger boards again.
        // Book two opens on a deliberate reset: its shapes are far denser than
        // Mastery's, and holding book one's swatch count through them asked a
        // player for thirty blind decisions per board, which measured as three
        // boards in a hundred read correctly on a first pass. The reset is the
        // sawtooth at book scale, so it is asserted rather than merely allowed.
        let bookOneEnd = 100
        let bookStart = CampaignCatalog.chapters.first { $0.first > bookOneEnd }?.title
        var previousAverage = 0.0
        for chapter in CampaignCatalog.chapters {
            let levels = CampaignCatalog.levels(in: chapter)
            let average = Double(levels.reduce(0) { $0 + $1.bankCount }) / Double(levels.count)
            if chapter.title == bookStart || chapter.title == "Spare Parts" {
                XCTAssertLessThan(average, previousAverage,
                                  "\(chapter.title) should open with a deliberate reset")
            } else {
                XCTAssertGreaterThan(average, previousAverage,
                                     "chapter \(chapter.title) doesn't step up")
            }
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
        XCTAssertNil(game.customTitle,
                     "campaign boards carry no authored shape name")
        XCTAssertNotNil(game.puzzle)
        XCTAssertFalse(game.generating, "authored levels don't wait on the generator")
        XCTAssertTrue(game.demoRunning, "level 1 introduces the drag")
        game.finishTeachingDemo()

        // Skip stays on the same level — there is no alternate board.
        game.handleSkip()
        XCTAssertEqual(game.campaignIndex, 1)

        // Solve → next level, and the clear is recorded.
        game.handleNext()
        XCTAssertEqual(game.campaignIndex, 2)
        XCTAssertTrue(CampaignStore.isCleared(1))
        XCTAssertNil(game.customTitle)
        XCTAssertFalse(game.campaignComplete)

        // A tip only ever shows once.
        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertNil(game.campaignTip)

        // The finale ends the campaign rather than advancing past the end.
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
        // Mark every tip seen up front. A first visit to an introducing
        // level plays the teaching demo, which paints the board solved
        // and empties the bank for a beat — reading the bank mid-demo
        // sees no swatches and reports the level as unplayable.
        for entry in CampaignCatalog.levels { CampaignStore.markTipSeen(entry.index) }
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

            // The red herrings, and only those, are left over.
            let expectedLeftover = puzzle.decoys.count
            let leftover = game.puzzle?.bank.compactMap { $0 }.count ?? -1
            if leftover != expectedLeftover {
                failures.append("\(entry.index) \(entry.name): \(leftover) swatches "
                                + "left in the bank after filling every cell, "
                                + "against \(expectedLeftover) decoys")
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
        XCTAssertNil(game.customTitle)
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
        for chapter in CampaignCatalog.chapters {
            XCTAssertTrue(CampaignStore.isUnlocked(chapter.first),
                          "the first level of every chapter is replayable")
        }
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

    /// Tapping or dragging a swatch selects it and reports a guidance
    /// dismissal, without spending the action that did it.
    ///
    /// Loads with the tip already marked seen. A first visit plays the
    /// teaching demo, which paints the board solved and empties the bank
    /// for a beat — so on a fresh install there is no swatch to tap yet,
    /// and that is the demo working, not the bank being wrong.
    @MainActor
    func testGameplayTapAndDragDismissCampaignGuidanceWithoutConsumingAction() throws {
        CampaignStore.resetAll()
        CampaignStore.markTipSeen(1)
        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(1))
        let slot = try XCTUnwrap(game.puzzle?.bank.indices.first {
            game.puzzle?.bank[$0] != nil
        })

        let tapDismissal = game.gameplayGuidanceDismissalID
        game.tapSlot(slot)
        XCTAssertEqual(game.gameplayGuidanceDismissalID, tapDismissal + 1)
        XCTAssertEqual(game.selection?.kind, .bank(slot))

        CampaignStore.resetAll()
        CampaignStore.markTipSeen(1)
        XCTAssertTrue(game.loadCampaignLevel(1))
        let item = try XCTUnwrap(game.puzzle?.bank[slot])
        let dragDismissal = game.gameplayGuidanceDismissalID
        game.beginDrag(DragSource(kind: .bank(slot), color: item.color), at: .zero)
        XCTAssertEqual(game.gameplayGuidanceDismissalID, dragDismissal + 1)
        XCTAssertEqual(game.dragSource?.kind, .bank(slot))
        CampaignStore.resetAll()
    }

    func testCampaignTipBannerDoesNotInterceptGameplay() throws {
        let banner = try source("ChromaticOrder/Views/CampaignTipBanner.swift")
        XCTAssertTrue(banner.contains(".allowsHitTesting(false)"))
        XCTAssertFalse(banner.contains(".onTapGesture"),
                       "the banner must not consume a dismiss-only tap")
        XCTAssertFalse(banner.contains(".contentShape(Rectangle())"),
                       "the banner must not install a full-screen hit target")
    }

    func testTutorialBalloonDoesNotInterceptGameplay() throws {
        let source = try source("ChromaticOrder/Views/TutorialOverlay.swift")
        let start = try XCTUnwrap(source.range(of: "struct TutorialBalloon: View"))
        let end = try XCTUnwrap(source.range(of: "struct BalloonStringToTargetShape"))
        let balloon = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(balloon.contains(".allowsHitTesting(false)"))
        XCTAssertFalse(balloon.contains(".simultaneousGesture("),
                       "non-decision guidance must not own gameplay drags")
        XCTAssertFalse(balloon.contains(".onTapGesture"),
                       "non-decision guidance must not own gameplay taps")
    }

    func testGameplayDismissalGracefullyReleasesTutorial() throws {
        // Every dismissal path — the spotlighted target, or tapping
        // elsewhere on the dimmed field — now floats the balloon away
        // via the same release animation used everywhere else
        // (menu-open, level-change), instead of hard-cutting it.
        // dismissTutorialImmediately() (the old abrupt-cut path) is
        // gone; gameplay actions release through the same function
        // as every other dismissal trigger.
        let content = try source("ChromaticOrder/ContentView.swift")
        XCTAssertTrue(content.contains(
            ".onChange(of: game.gameplayGuidanceDismissalID) { _, _ in"
        ))
        XCTAssertTrue(content.contains("releaseTutorial()"))
        XCTAssertFalse(content.contains("dismissTutorialImmediately"),
                       "the abrupt hard-cut path should no longer exist")
        XCTAssertTrue(content.contains("tutorialPresentationID == presentationID"),
                      "a delayed callback must identify the exact presentation instance")
    }

    func testStaleTutorialCompletionCannotUnmountSameFlagRePresentation() throws {
        let first = TutorialPresentationToken(flag: .firstLaunch, id: 1)
        let represented = TutorialPresentationToken(flag: .firstLaunch, id: 3)

        XCTAssertFalse(first.matches(activeFlag: represented.flag,
                                     activePresentationID: represented.id))
        XCTAssertTrue(represented.matches(activeFlag: represented.flag,
                                          activePresentationID: represented.id))
        XCTAssertFalse(represented.matches(activeFlag: .dailyIntro,
                                           activePresentationID: represented.id))
    }

    func testLegacyOnboardingUsesUnifiedGameplayDismissalPath() throws {
        let onboarding = try source("ChromaticOrder/Views/OnboardingOverlay.swift")
        XCTAssertTrue(onboarding.contains("game.gameplayGuidanceDismissalID"))
        XCTAssertTrue(onboarding.contains("seen = true"))
        XCTAssertTrue(onboarding.contains(".allowsHitTesting(false)"))
    }

    func testMeaningfulGuidanceAvoidsThirteenPointType() throws {
        for path in [
            "ChromaticOrder/Views/BankView.swift",
            "ChromaticOrder/Views/OnboardingOverlay.swift",
            "ChromaticOrder/Views/TutorialOverlay.swift",
        ] {
            let text = try source(path)
            XCTAssertFalse(text.contains(".font(.system(size: 13"),
                           "meaningful coaching remains 13pt in \(path)")
        }
    }

    @MainActor
    func testInvalidBankDragReturnsToOriginalSlotWithoutMutatingState() throws {
        CampaignStore.resetAll()
        CampaignStore.markTipSeen(1)   // skip the teaching demo; see above
        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(1))
        let slot = try XCTUnwrap(game.puzzle?.bank.indices.first {
            game.puzzle?.bank[$0] != nil
        })
        let beforeBank = try XCTUnwrap(game.puzzle?.bank)
        let beforeSelection = game.selection
        let beforeMoves = game.moveCount
        let item = try XCTUnwrap(beforeBank[slot])

        game.beginDrag(DragSource(kind: .bank(slot), color: item.color), at: .zero)
        game.endDrag(moved: true)

        XCTAssertEqual(game.puzzle?.bank, beforeBank)
        XCTAssertEqual(game.selection, beforeSelection)
        XCTAssertEqual(game.moveCount, beforeMoves)
        XCTAssertEqual(game.bankReturnSlot, slot)
        CampaignStore.resetAll()
    }

    func testCampaignExplorePresentationUsesChapterLocalNumberingAndCounts() throws {
        CampaignStore.resetAll()
        for chapter in CampaignCatalog.chapters {
            XCTAssertEqual(CampaignStore.chapterCompletion(chapter), 0)
            XCTAssertEqual(CampaignStore.localNumber(for: chapter.first), 1)
            XCTAssertEqual(CampaignStore.localNumber(for: chapter.last), chapter.count)
        }

        let chapter = try XCTUnwrap(CampaignCatalog.chapters.dropFirst().first)
        CampaignStore.markCleared(chapter.first)
        XCTAssertEqual(CampaignStore.chapterCompletion(chapter), 1)
        CampaignStore.resetAll()
    }

    /// The campaign header is progression, not a picture caption. No level
    /// may leak its authored shape name into the title the top bar renders,
    /// at any point in the campaign — the header shows the chapter and the
    /// chip shows the position, and both come from the catalog, not `name`.
    @MainActor
    func testCampaignLevelsCarryNoAuthoredShapeName() throws {
        let game = GameState()
        for index in [1, 2, 33, 100, 101, 200, CampaignCatalog.count] {
            let entry = try XCTUnwrap(CampaignCatalog.level(index))
            XCTAssertTrue(game.loadCampaignLevel(entry.index))
            XCTAssertNil(game.customTitle,
                         "level \(index) put '\(entry.name)' in the top bar")
            XCTAssertNotNil(CampaignCatalog.chapter(containing: index)?.title,
                            "level \(index) has no chapter to name instead")
        }
        CampaignStore.resetAll()
    }

    /// Chapter titles are the campaign's visible ladder, so they must name a
    /// step in it rather than what the boards happen to depict. Locks the
    /// shipped set against a regeneration quietly restoring the old ones.
    func testChapterTitlesAreProgressionLed() throws {
        let retired: Set<String> = [
            "Everyday Things", "Creatures", "Landmarks",
            "Workshop", "Orchestra", "Circuitry", "Interiors", "Grand Works",
        ]
        let titles = CampaignCatalog.chapters.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "chapter titles must be unique")
        for title in titles {
            XCTAssertFalse(retired.contains(title),
                           "\(title) is a picture-led chapter title")
        }
        // Every level agrees with the chapter that owns its index, so the
        // picker's "\(chapter), level \(n)" label can never disagree with
        // the header the board shows.
        for level in CampaignCatalog.levels {
            let owner = try XCTUnwrap(CampaignCatalog.chapter(containing: level.index))
            XCTAssertEqual(level.chapter, owner.title,
                           "level \(level.index) claims chapter \(level.chapter)")
        }
    }

    /// A level that introduces something teaches by showing its solved
    /// board and taking it apart, not by printing a sentence over it.
    /// This used to assert that Check dismissed that sentence.
    @MainActor
    func testAnIntroducingLevelPlaysItsTeachingDemoOnceOnly() throws {
        CampaignStore.resetAll()
        let game = GameState()

        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertTrue(game.demoRunning, "level 1 introduces the drag")
        XCTAssertNil(game.campaignTip, "the sentence is gone; the demo replaced it")

        game.finishTeachingDemo()
        XCTAssertFalse(game.demoRunning)

        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertFalse(game.demoRunning, "a replay does not teach again")
        CampaignStore.resetAll()
    }

    /// Strategy notes remain useful authoring metadata, but they must not
    /// reveal a puzzle's exact answer. The demo list is deliberately short
    /// and explicit, and the campaign finale is always earned cold.
    @MainActor
    func testOnlyMechanicIntroductionsPlayTeachingDemos() throws {
        let demos = CampaignCatalog.levels.filter(\.shouldPlayTeachingDemo)
        XCTAssertEqual(demos.map(\.index), [1, 2, 7, 10, 53, 161])
        XCTAssertTrue(demos.allSatisfy { $0.tip != nil })

        let finale = try XCTUnwrap(CampaignCatalog.level(CampaignCatalog.count))
        XCTAssertFalse(finale.shouldPlayTeachingDemo)

        CampaignStore.resetAll()
        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(finale.index))
        XCTAssertFalse(game.demoRunning, "the finale must not reveal its solution")
        CampaignStore.resetAll()
    }

    /// The red-herring lesson has one fact an ordinary solved-board demo
    /// cannot teach: the board can be complete while the bank is not empty.
    /// Keep the spare on screen while every real colour is shown in place.
    @MainActor
    func testRedHerringTeachingDemoLeavesItsSpareVisible() throws {
        let entry = try XCTUnwrap(CampaignCatalog.levels.first {
            $0.shouldPlayTeachingDemo && !($0.doc.decoys ?? []).isEmpty
        })

        CampaignStore.resetAll()
        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(entry.index))
        XCTAssertTrue(game.demoRunning)

        let puzzle = try XCTUnwrap(game.puzzle)
        XCTAssertTrue(puzzle.everyFreeCellIsFilled)
        XCTAssertEqual(puzzle.bank.compactMap { $0 }.count, puzzle.decoys.count,
                       "the solved demonstration should leave only the spare visible")

        game.finishTeachingDemo()
        let reset = try XCTUnwrap(game.puzzle)
        XCTAssertFalse(reset.everyFreeCellIsFilled)
        XCTAssertEqual(reset.bank.compactMap { $0 }.count, reset.initialBankCount)
        CampaignStore.resetAll()
    }

    /// The solved teaching frame is presentation, never progress. A lifecycle
    /// save during the beat must leave the clean checkpoint untouched.
    @MainActor
    func testTeachingDemoNeverPersistsItsRevealedSolution() throws {
        InProgressSessionStore.clear()
        CampaignStore.resetAll()
        defer {
            InProgressSessionStore.clear()
            CampaignStore.resetAll()
        }

        let entry = try XCTUnwrap(CampaignCatalog.level(1))
        let startingPuzzle = try XCTUnwrap(entry.puzzle())
        let startingPlacements = startingPuzzle.board.flatMap { $0 }.filter {
            $0.kind == .cell && $0.placed != nil
        }.count
        let startingBank = startingPuzzle.bank.compactMap { $0 }.count

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(entry.index))
        XCTAssertTrue(game.demoRunning)
        XCTAssertTrue(game.puzzle?.everyFreeCellIsFilled ?? false)

        let beforeLifecycleSave = try XCTUnwrap(InProgressSessionStore.load())
        XCTAssertEqual(beforeLifecycleSave.campaignIndex, entry.index)
        XCTAssertEqual(beforeLifecycleSave.placements.count, startingPlacements)
        XCTAssertEqual(beforeLifecycleSave.bank.compactMap { $0 }.count, startingBank)

        game.persistInProgressSession(autoResume: true)
        let afterLifecycleSave = try XCTUnwrap(InProgressSessionStore.load())
        XCTAssertEqual(afterLifecycleSave.savedAt, beforeLifecycleSave.savedAt,
                       "mid-demo persistence must leave the clean checkpoint untouched")
        XCTAssertEqual(afterLifecycleSave.placements.count, startingPlacements)
        XCTAssertEqual(afterLifecycleSave.bank.compactMap { $0 }.count, startingBank)

        game.finishTeachingDemo()
    }

    /// A delayed completion belongs to the demo that created it. Loading a
    /// second introducing level must invalidate the first level's task.
    @MainActor
    func testStaleTeachingDemoCannotFinishANewerDemo() async throws {
        InProgressSessionStore.clear()
        CampaignStore.resetAll()
        defer {
            InProgressSessionStore.clear()
            CampaignStore.resetAll()
        }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertTrue(game.demoRunning)

        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(game.loadCampaignLevel(2))
        XCTAssertTrue(game.demoRunning)

        // Level 1's completion fires 0.7 seconds into level 2's 1.4-second
        // beat. It must notice that its run token is stale and do nothing.
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(game.demoRunning)
        XCTAssertEqual(game.campaignIndex, 2)

        game.finishTeachingDemo()
    }
}
