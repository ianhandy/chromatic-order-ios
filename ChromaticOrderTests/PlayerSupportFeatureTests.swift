import XCTest
@testable import ChromaticOrder

final class PlayerSupportFeatureTests: XCTestCase {
    func testLockedFeatureMessagesExplainWhatUnlocks() {
        XCTAssertEqual(FullVersionFeature.campaign.title, "the full campaign")
        XCTAssertTrue(FullVersionFeature.campaign.detail.contains("200"))
        XCTAssertTrue(FullVersionFeature.zen.detail.contains("infinite"))
        XCTAssertTrue(FullVersionFeature.zen.detail.contains("procedurally generated"))
        XCTAssertTrue(FullVersionFeature.zen.detail.contains("difficulty"))
        XCTAssertTrue(FullVersionFeature.challenge.detail.contains("three hearts"))
        XCTAssertTrue(FullVersionFeature.creator.detail.contains("build and share"))
    }

    func testFullVersionLeavesFourCampaignChaptersAndDailyFree() throws {
        let fourth = try XCTUnwrap(CampaignCatalog.chapters.dropFirst(3).first)
        let fifth = try XCTUnwrap(CampaignCatalog.chapters.dropFirst(4).first)

        XCTAssertEqual(FullVersionAccess.lastFreeCampaignLevel, fourth.last)
        XCTAssertFalse(FullVersionAccess.campaignLevelRequiresPurchase(fourth.last))
        XCTAssertTrue(FullVersionAccess.campaignLevelRequiresPurchase(fifth.first))
        XCTAssertFalse(FullVersionAccess.modeRequiresPurchase(.daily))
        XCTAssertTrue(FullVersionAccess.modeRequiresPurchase(.zen))
        XCTAssertTrue(FullVersionAccess.modeRequiresPurchase(.challenge))
        XCTAssertFalse(FullVersionAccess.sessionRequiresPurchase(
            campaignIndex: fourth.last,
            mode: .zen
        ))
        XCTAssertTrue(FullVersionAccess.sessionRequiresPurchase(
            campaignIndex: fifth.first,
            mode: .zen
        ))
        XCTAssertFalse(FullVersionAccess.sessionRequiresPurchase(
            campaignIndex: nil,
            mode: .zen,
            isCustomPuzzle: true
        ))
        XCTAssertFalse(FullVersionAccess.sessionRequiresPurchase(
            campaignIndex: nil,
            mode: .challenge,
            isTrialSession: true
        ))
    }

    @MainActor
    func testTrialsRemainAvailableUntilExplicitlyCompleted() {
        FullVersionTrialStore.reset()
        defer { FullVersionTrialStore.reset() }

        let store = FullVersionStore()
        XCTAssertTrue(store.canTry(.zen))
        XCTAssertTrue(store.canTry(.challenge))
        XCTAssertTrue(store.canTry(.creator))

        store.completeTrial(.zen)
        XCTAssertFalse(store.canTry(.zen))
        XCTAssertTrue(store.hasTried(.zen))
        XCTAssertTrue(store.canTry(.challenge))
        XCTAssertTrue(store.canTry(.creator))
    }

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
    func testTrialSessionRoundTripDoesNotConsumeTheTrial() {
        InProgressSessionStore.clear()
        FullVersionTrialStore.reset()
        defer {
            InProgressSessionStore.clear()
            FullVersionTrialStore.reset()
        }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        game.isTrialSession = true
        game.persistInProgressSession(autoResume: true)

        let restored = GameState()
        XCTAssertTrue(restored.isTrialSession)
        XCTAssertFalse(FullVersionTrialStore.hasCompleted(.zen))
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
        XCTAssertEqual(game.hintedCells.count, 1)
        XCTAssertNotNil(game.hintedBankSlot)
        XCTAssertEqual(game.hintMessage, "place this swatch here")
        if let target = game.hintedCells.first,
           let slot = game.hintedBankSlot,
           let solution = game.puzzle?.board[target.r][target.c].solution,
           let swatch = game.puzzle?.bank[slot] {
            XCTAssertTrue(game.sameColor(solution, swatch.color))
        } else {
            XCTFail("hint should pair one target cell with its matching swatch")
        }
        XCTAssertEqual(game.puzzle?.board, beforeBoard)
        XCTAssertEqual(game.puzzle?.bank, beforeBank)

        game.requestHint()
        XCTAssertEqual(game.hintStage, 2)
        XCTAssertNotNil(game.hintedBankSlot)
        XCTAssertEqual(game.puzzle?.board, beforeBoard)
        XCTAssertEqual(game.puzzle?.bank, beforeBank)
    }

    func testDailyHistoryAndCampaignBookmarksPersist() {
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
        XCTAssertEqual(CampaignStore.lastPlayed, 4)
    }

    func testCampaignResumeChapterFollowsFirstUnclearedLevel() throws {
        CampaignStore.resetAll()
        defer { CampaignStore.resetAll() }

        let firstChapter = try XCTUnwrap(CampaignCatalog.chapters.first)
        XCTAssertEqual(CampaignStore.resumeChapter?.id, firstChapter.id)

        for index in firstChapter.levelRange.dropLast() {
            CampaignStore.markCleared(index)
        }
        XCTAssertEqual(CampaignStore.resumeChapter?.id, firstChapter.id)

        CampaignStore.markCleared(firstChapter.last)
        let nextChapter = try XCTUnwrap(CampaignCatalog.chapters.dropFirst().first)
        XCTAssertEqual(CampaignStore.resumeChapter?.id, nextChapter.id)
    }

    @MainActor
    func testSavedGalleryPuzzleCannotBeFavoritedAgain() throws {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let puzzle = try XCTUnwrap(CampaignCatalog.level(1)?.puzzle())
        let game = GameState()
        game.loadCustomPuzzle(
            puzzle,
            fromGallery: true,
            galleryPuzzleId: "saved-level",
            allowsFavorite: false
        )

        XCTAssertTrue(game.isCustomPuzzle)
        XCTAssertFalse(game.canSaveCurrentPuzzle)
        game.toggleCurrentPuzzleSaved()
        XCTAssertNil(game.currentFavoriteURL)
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
