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

    func testDailyStreakAllowsTodayToRemainOpenAndPreservesLongestRun() {
        DailyHistoryStore.reset()
        defer { DailyHistoryStore.reset() }

        for key in ["2026-08-14", "2026-08-15", "2026-08-16"] {
            DailyHistoryStore.recordCompletion(
                key, solveSeconds: 60, moveCount: 8,
                clean: true, usedHint: false
            )
        }

        let august17 = ISO8601DateFormatter().date(from: "2026-08-17T12:00:00Z")!
        let august18 = ISO8601DateFormatter().date(from: "2026-08-18T12:00:00Z")!
        XCTAssertEqual(DailyHistoryStore.streakSummary(now: august17).longest, 3)
        XCTAssertEqual(DailyHistoryStore.streakSummary(now: august17).current, 3)

        DailyHistoryStore.recordCompletion(
            "2026-08-17", solveSeconds: 58, moveCount: 7,
            clean: true, usedHint: false
        )
        XCTAssertEqual(DailyHistoryStore.streakSummary(now: august17).current, 4)
        XCTAssertEqual(DailyHistoryStore.streakSummary(now: august18).current, 4)

        let august19 = ISO8601DateFormatter().date(from: "2026-08-19T12:00:00Z")!
        let expired = DailyHistoryStore.streakSummary(now: august19)
        XCTAssertEqual(expired.current, 0)
        XCTAssertEqual(expired.longest, 4)
    }

    func testReminderFallsTwoHoursBeforeUTCReset() {
        let noon = ISO8601DateFormatter().date(from: "2026-08-17T12:00:00Z")!
        let late = ISO8601DateFormatter().date(from: "2026-08-17T23:00:00Z")!
        let expectedToday = ISO8601DateFormatter().date(from: "2026-08-17T22:00:00Z")!
        let expectedTomorrow = ISO8601DateFormatter().date(from: "2026-08-18T22:00:00Z")!

        XCTAssertEqual(StreakReminderStore.nextReminderDate(now: noon), expectedToday)
        XCTAssertEqual(StreakReminderStore.nextReminderDate(now: late), expectedTomorrow)
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
