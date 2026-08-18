import XCTest
@testable import ChromaticOrder

final class PlayerSupportFeatureTests: XCTestCase {
    @MainActor
    func testExactSessionRoundTripPreservesLiveBoardAndContext() throws {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        guard var puzzle = game.puzzle,
              let bankSlot = puzzle.bank.firstIndex(where: { $0 != nil }),
              let item = puzzle.bank[bankSlot],
              let target = firstFreeCell(in: puzzle) else {
            return XCTFail("campaign level needs a free cell and bank item")
        }
        puzzle.board[target.r][target.c].placed = item.color
        puzzle.bank[bankSlot] = nil
        game.puzzle = puzzle
        game.moveCount = 7
        game.mistakeCount = 2
        game.persistInProgressSession(autoResume: true)
        game.solved = true

        let restored = GameState()
        XCTAssertEqual(restored.campaignIndex, 5)
        XCTAssertEqual(restored.moveCount, 7)
        XCTAssertEqual(restored.mistakeCount, 2)
        XCTAssertTrue(restored.shouldAutoResumeSession)
        XCTAssertTrue(restored.solved)
        XCTAssertEqual(restored.puzzle?.board[target.r][target.c].placed, item.color)
        XCTAssertNil(restored.puzzle?.bank[bankSlot])
    }

    @MainActor
    func testHintsNarrowWithoutPlacingAColor() {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        let beforeBoard = game.puzzle?.board
        let beforeBank = game.puzzle?.bank

        game.requestHint()
        XCTAssertTrue(game.usedHintThisLevel)
        XCTAssertEqual(game.hintStage, 1)
        XCTAssertFalse(game.hintedCells.isEmpty)
        XCTAssertEqual(game.puzzle?.board, beforeBoard)
        XCTAssertEqual(game.puzzle?.bank, beforeBank)

        game.requestHint()
        XCTAssertEqual(game.hintStage, 2)
        XCTAssertNotNil(game.hintedBankSlot)
        XCTAssertEqual(game.puzzle?.board, beforeBoard)
        XCTAssertEqual(game.puzzle?.bank, beforeBank)
    }

    func testDailyHistoryAndCampaignQuickAccessPersist() {
        DailyHistoryStore.reset()
        CampaignStore.resetAll()
        defer {
            DailyHistoryStore.reset()
            CampaignStore.resetAll()
        }

        DailyHistoryStore.recordAttempt("2026-08-16")
        DailyHistoryStore.recordCompletion(
            "2026-08-16", solveSeconds: 91, moveCount: 12,
            clean: true, usedHint: false
        )
        let daily = DailyHistoryStore.entries().first
        XCTAssertEqual(daily?.dateKey, "2026-08-16")
        XCTAssertEqual(daily?.solveSeconds, 91)
        XCTAssertEqual(daily?.clean, true)

        CampaignStore.toggleBookmark(3)
        CampaignStore.recordPlayed(3)
        CampaignStore.recordPlayed(4)
        XCTAssertEqual(CampaignStore.bookmarks, [3])
        XCTAssertEqual(Array(CampaignStore.recent.prefix(2)), [4, 3])
    }

    private func firstFreeCell(in puzzle: Puzzle) -> CellIndex? {
        for r in 0..<puzzle.gridH {
            for c in 0..<puzzle.gridW {
                let cell = puzzle.board[r][c]
                if cell.kind == .cell && !cell.locked { return CellIndex(r: r, c: c) }
            }
        }
        return nil
    }
}
