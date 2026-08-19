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
        // The offer is explained once, at the moment it is spent — the
        // main menu carries no standing paragraph about it.
        XCTAssertTrue(Strings.Menu.trialTitleZen.contains("full version"))
        XCTAssertTrue(Strings.Menu.trialTitleChallenge.contains("full version"))
        XCTAssertTrue(Strings.Menu.trialOfferBody.contains("as many levels as you like"))
        XCTAssertTrue(Strings.Menu.trialOfferBody.contains("leave for the menu"))
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
    func testEndingATrialRunClearsItsResumeWithoutConsumingAnotherMode() {
        InProgressSessionStore.clear()
        FullVersionTrialStore.reset()
        defer {
            InProgressSessionStore.clear()
            FullVersionTrialStore.reset()
        }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        game.mode = .zen
        game.isTrialSession = true
        game.persistInProgressSession(autoResume: false)
        XCTAssertTrue(game.hasInProgressSession)

        game.endTrialRun()

        XCTAssertFalse(game.isTrialSession)
        XCTAssertFalse(game.hasInProgressSession)
        XCTAssertFalse(FullVersionTrialStore.hasCompleted(.challenge))
    }

    @MainActor
    func testChallengePerfectMeansCorrectOnFirstCheckNotFirstPlacement() {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        game.mode = .challenge
        game.solved = true
        game.mistakeCount = 8
        game.moveCount = 99
        game.heartLostThisLevel = false

        XCTAssertTrue(game.isPerfectSolve)

        game.heartLostThisLevel = true
        XCTAssertFalse(game.isPerfectSolve)
    }

    @MainActor
    func testEnjoymentPromptBecomesEligibleAfterThreeDistinctLocalDays() {
        let defaults = isolatedDefaults()
        let calendar = utcCalendar()
        let store = PlayerEngagementStore(defaults: defaults, calendar: calendar)
        let dates = [
            "2026-08-17T12:00:00Z",
            "2026-08-18T12:00:00Z",
            "2026-08-19T12:00:00Z",
        ].compactMap(ISO8601DateFormatter().date(from:))

        store.appDidBecomeActive(now: dates[0])
        store.appDidResignActive(now: dates[0])
        store.appDidBecomeActive(now: dates[1])
        store.appDidResignActive(now: dates[1])
        XCTAssertFalse(store.isEligible(now: dates[1]))

        store.appDidBecomeActive(now: dates[2])
        store.menuDidAppear(now: dates[2])

        XCTAssertEqual(store.openedDayCount, 3)
        XCTAssertTrue(store.isPromptPresented)
    }

    @MainActor
    func testEnjoymentPromptCountsOnlyActiveGameplayTowardOneHour() {
        let defaults = isolatedDefaults()
        let store = PlayerEngagementStore(defaults: defaults, calendar: utcCalendar())
        let start = ISO8601DateFormatter().date(from: "2026-08-19T12:00:00Z")!

        store.appDidBecomeActive(now: start)
        store.gameplayDidStart(now: start)
        store.gameplayDidEnd(now: start.addingTimeInterval(3_600))
        store.menuDidAppear(now: start.addingTimeInterval(3_600))

        XCTAssertEqual(store.cumulativeGameplaySeconds, 3_600, accuracy: 0.01)
        XCTAssertTrue(store.isPromptPresented)
    }

    @MainActor
    func testEnjoymentResponsesPersistTheRequestedOneVisitMenuNudge() {
        let defaults = isolatedDefaults()
        let store = PlayerEngagementStore(defaults: defaults, calendar: utcCalendar())

        store.menuDidAppear()
        store.recordResponse(.yes)
        XCTAssertEqual(store.rateUsLabel, Strings.Menu.rateUsPlease)
        XCTAssertEqual(store.activeMenuNudge, .rate)

        store.menuDidDisappear()
        XCTAssertNil(store.activeMenuNudge)

        let restored = PlayerEngagementStore(defaults: defaults, calendar: utcCalendar())
        XCTAssertEqual(restored.response, .yes)
        restored.menuDidAppear()
        XCTAssertNil(restored.activeMenuNudge)
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

    @MainActor
    func testShowIncorrectStaysHiddenUntilTheBoardHasAPlayerPlacement() {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        XCTAssertFalse(game.hasPlacedSwatch,
                       "an untouched board offers nothing for show-incorrect to say")

        guard let free = firstFreeCell(in: game.puzzle!) else {
            return XCTFail("campaign level 5 has no free cell")
        }
        game.puzzle?.board[free.r][free.c].placed = OKLCh(L: 0.5, c: 0.1, h: 200)
        XCTAssertTrue(game.hasPlacedSwatch)
    }

    @MainActor
    func testLockedGivensDoNotCountAsAPlayerPlacement() {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        // Campaign levels ship with revealed cells already filled in.
        // Those are the puzzle's, not the player's.
        let hasLockedFill = game.puzzle!.board.contains { row in
            row.contains { $0.kind == .cell && $0.locked && $0.placed != nil }
        }
        XCTAssertTrue(hasLockedFill, "level 5 should have revealed starter cells")
        XCTAssertFalse(game.hasPlacedSwatch)
    }

    @MainActor
    func testPerfectSolveHeartStopsAtTheBankCeiling() {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(5))
        game.mode = .challenge
        game.campaignIndex = nil
        game.solved = true
        game.heartLostThisLevel = false
        game.checks = GameState.maxChecks

        game.handleNext()

        XCTAssertEqual(game.checks, GameState.maxChecks,
                       "perfect now means 'did not fail the check', so the bank must not ratchet forever")
    }

    @MainActor
    func testChallengePaysOneBonusLadderNotTwoForTheSameSolve() {
        InProgressSessionStore.clear()
        defer { InProgressSessionStore.clear() }

        let game = GameState()
        game.mode = .challenge
        game.campaignIndex = nil
        game.challengeBonusLevels = 0

        // Three clean solves in a row. Perfect and no-heart are now the
        // same event, so exactly one ladder may pay out.
        for _ in 0..<3 {
            XCTAssertTrue(game.loadCampaignLevel(5))
            game.mode = .challenge
            game.campaignIndex = nil
            game.solved = true
            game.heartLostThisLevel = false
            game.handleNext()
        }

        XCTAssertEqual(game.challengeBonusLevels, 1)
    }

    @MainActor
    func testCustomDifficultyIndicatorsAreHidden() {
        XCTAssertFalse(CustomDifficultyDisplay.isVisible)
        XCTAssertFalse(KromaPuzzleFile(json: "{}", difficulty: 7)
            .suggestedFilename.contains("7"))
        XCTAssertFalse(KromaPuzzleFile.shareTitle(difficulty: 7).contains("7"))
    }

    @MainActor
    func testRecoloringASelectedGradientRepaintsBetweenItsNewEnds() {
        let state = CreatorState()
        let cells = (0..<4).map { CellIndex(r: 2, c: 2 + $0) }
        state.gradients = [
            LaidGradient(dir: .h, cells: cells,
                         colors: cells.map { _ in OKLCh(L: 0.5, c: 0.1, h: 30) })
        ]
        state.selectedCells = Set(cells)
        XCTAssertNotNil(state.selectedGradient)

        let newStart = OKLCh(L: 0.30, c: 0.12, h: 20)
        let newEnd = OKLCh(L: 0.80, c: 0.12, h: 200)
        state.setSelectedColor(newStart, at: .start)
        state.setSelectedColor(newEnd, at: .end)

        let painted = state.gradients[0].colors
        XCTAssertEqual(painted.count, 4)
        XCTAssertEqual(painted.first!.L, newStart.L, accuracy: 0.0001)
        XCTAssertEqual(painted.last!.L, newEnd.L, accuracy: 0.0001)
        // The interior has to actually travel, not just inherit an end.
        XCTAssertTrue(painted[1].L > painted[0].L && painted[1].L < painted[2].L)
        XCTAssertTrue(painted[2].L < painted[3].L)
    }

    @MainActor
    func testChipsOnlyRetargetWhenExactlyOneGradientIsSelected() {
        let state = CreatorState()
        let a = (0..<3).map { CellIndex(r: 1, c: 1 + $0) }
        let b = (0..<3).map { CellIndex(r: 5, c: 1 + $0) }
        state.gradients = [
            LaidGradient(dir: .h, cells: a, colors: a.map { _ in OKLCh(L: 0.4, c: 0.1, h: 10) }),
            LaidGradient(dir: .h, cells: b, colors: b.map { _ in OKLCh(L: 0.6, c: 0.1, h: 90) })
        ]

        state.selectedCells = []
        XCTAssertNil(state.selectedGradient, "no selection means the chips arm the next stroke")

        state.selectedCells = Set(a + b)
        XCTAssertNil(state.selectedGradient, "an ambiguous selection must not silently repaint one of them")

        state.selectedCells = Set(a)
        XCTAssertNotNil(state.selectedGradient)
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

    private func isolatedDefaults() -> UserDefaults {
        let suite = "PlayerSupportFeatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
