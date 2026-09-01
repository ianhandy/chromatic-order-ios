//  A board carrying a red herring has more swatches than cells, and
//  placement conserves swatches, so its bank never empties. Everything
//  that used to mean "the player is done" by asking the bank has to ask
//  the board instead. Check was the one that didn't, and gating it on an
//  empty bank made every generated level from `decoyFirstGeneratedLevel`
//  on impossible to submit — skip only dealt another board at the same
//  level, so a challenge run simply ended there.

import XCTest
@testable import ChromaticOrder

final class DecoyPlayabilityTests: XCTestCase {

    /// Fill every cell of a decoy board and the board must read as full
    /// even though a swatch is still sitting in the bank.
    @MainActor
    func testAFilledDecoyBoardReadsAsFullWithASwatchStillInTheBank() {
        let game = GameState()
        game.enterMode(.challenge)

        var found: Puzzle?
        // makeDecoys can come back empty when a palette leaves no room for
        // a fair spare, so take the first board that actually has one
        // rather than assuming any single level does.
        for level in decoyFirstGeneratedLevel...(decoyFirstGeneratedLevel + 8) {
            game.startLevel(level)
            waitForGeneration(game)
            if let p = game.puzzle, !p.decoys.isEmpty { found = p; break }
        }
        guard let puzzle = found else {
            return XCTFail("no level in range generated a decoy to test with")
        }

        XCTAssertFalse(puzzle.everyFreeCellIsFilled,
                       "a fresh board starts with empty cells")

        fillEveryFreeCell(game)

        let leftover = game.puzzle?.bank.compactMap { $0 }.count ?? 0
        XCTAssertEqual(leftover, puzzle.decoys.count,
                       "the decoys, and only the decoys, stay behind")
        XCTAssertTrue(game.puzzle?.everyFreeCellIsFilled ?? false,
                      "every cell has a swatch, so Check has to be available")
    }

    /// The same property for the authored red-herring chapter.
    @MainActor
    func testEveryRedHerringCampaignLevelCanBeFilled() {
        CampaignStore.resetAll()
        let game = GameState()
        var failures: [String] = []

        // Mark every teaching demo seen first. A level that introduces something
        // plays its teaching demo on load, which paints the board solved
        // and empties the bank for a beat — waiting that out 220 times
        // takes long enough to trip the test watchdog, and the demo is
        // not what this test is about.
        for entry in CampaignCatalog.levels { CampaignStore.markTipSeen(entry.index) }

        for entry in CampaignCatalog.levels {
            guard game.loadCampaignLevel(entry.index) else { continue }
            guard let puzzle = game.puzzle, !puzzle.decoys.isEmpty else { continue }

            fillEveryFreeCell(game)
            if !(game.puzzle?.everyFreeCellIsFilled ?? false) {
                failures.append("\(entry.index) \(entry.name): cells left empty")
            }
            let leftover = game.puzzle?.bank.compactMap { $0 }.count ?? -1
            if leftover != puzzle.decoys.count {
                failures.append("\(entry.index) \(entry.name): \(leftover) left in the "
                                + "bank against \(puzzle.decoys.count) decoys")
            }
        }

        CampaignStore.resetAll()
        XCTAssertTrue(failures.isEmpty,
                      "red-herring levels that cannot be filled:\n"
                      + failures.joined(separator: "\n"))
    }

    /// Later decoys follow eligible boards, not raw level numbers. Dense
    /// boards are omitted without consuming one of the three-board cadence
    /// slots, and the chapter opener remains a clean geometry introduction.
    func testRecurringCampaignDecoysUseEveryThirdEligibleBoard() {
        let later = CampaignCatalog.levels.filter { $0.index > 180 }
        let fairDecoyExclusions: Set<Int> = [198, 210, 213]
        let eligible = later.filter {
            $0.cellCount <= 45 && !fairDecoyExclusions.contains($0.index)
        }
        let expected = Set(eligible.enumerated().compactMap { offset, entry in
            offset % 3 == 1 ? entry.index : nil
        })
        let actual = Set(later.compactMap { entry in
            (entry.doc.decoys ?? []).isEmpty ? nil : entry.index
        })

        XCTAssertEqual(actual, expected)
        XCTAssertTrue(later.filter { $0.cellCount > 45 }.allSatisfy {
            ($0.doc.decoys ?? []).isEmpty
        })
        XCTAssertTrue(later.filter { fairDecoyExclusions.contains($0.index) }.allSatisfy {
            ($0.doc.decoys ?? []).isEmpty
        })

        let teaching = CampaignCatalog.levels.filter { (161...180).contains($0.index) }
        XCTAssertTrue(teaching.allSatisfy {
            (1...3).contains(($0.doc.decoys ?? []).count)
        })
    }

    // ─── helpers ────────────────────────────────────────────────────

    /// Drop swatches into cells in reading order until nothing is left to
    /// place. Deliberately not the *correct* placement — this is about
    /// whether the board can be filled at all, not whether it is right.
    @MainActor
    private func fillEveryFreeCell(_ game: GameState) {
        while let p = game.puzzle,
              let slot = p.bank.firstIndex(where: { $0 != nil }) {
            var placed = false
            search: for r in 0..<p.gridH {
                for c in 0..<p.gridW where p.board[r][c].kind == .cell
                    && !p.board[r][c].locked && p.board[r][c].placed == nil {
                    game.placeSlotIntoCell(slot, at: r, c)
                    placed = true
                    break search
                }
            }
            if !placed { break }
        }
    }

    @MainActor
    private func waitForGeneration(_ game: GameState) {
        let deadline = Date().addingTimeInterval(30)
        while game.generating && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}
