//  Guideline 1.2 moderation behavior.
//
//  The user-facing contract these lock down: reporting or blocking
//  takes effect on THIS device immediately and without a network
//  round-trip, because that's what makes the affordance real when the
//  backend is slow, down, or (for reports) not yet deployed.

import XCTest
@testable import ChromaticOrder

final class ModerationStoreTests: XCTestCase {

    private let keys = [
        "kromaBlockedSubmitters_v1",
        "kromaHiddenCommunityIds_v1",
        "kromaReportedCommunityIds_v1",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func entry(id: String, submitter: String?) -> CommunityPuzzleEntry {
        let cells = [
            CreatorPuzzleDoc.Cell(r: 0, c: 0, L: 0.6, C: 0.1, h: 30, locked: false),
            CreatorPuzzleDoc.Cell(r: 0, c: 1, L: 0.7, C: 0.1, h: 40, locked: false),
        ]
        let doc = CreatorPuzzleDoc(
            version: 1, gridW: 2, gridH: 1,
            gradients: [CreatorPuzzleDoc.Grad(dir: "h", cells: cells)]
        )
        return CommunityPuzzleEntry(id: id, doc: doc, level: 1,
                                    submitterName: submitter,
                                    upCount: 0, downCount: 0, score: 0,
                                    approvedAt: nil)
    }

    // MARK: - Blocking

    func testBlockHidesEverythingFromThatSubmitter() {
        let feed = [entry(id: "a", submitter: "Ada"),
                    entry(id: "b", submitter: "Grace"),
                    entry(id: "c", submitter: "Ada")]
        ModerationStore.block(name: "Ada")
        let visible = ModerationStore.filterCommunity(feed)
        XCTAssertEqual(visible.map(\.id), ["b"],
                       "both of Ada's puzzles should disappear, not just the reported one")
    }

    func testBlockIsCaseAndWhitespaceInsensitive() {
        ModerationStore.block(name: "Ada")
        XCTAssertTrue(ModerationStore.isBlocked(name: "  ada  "))
        XCTAssertTrue(ModerationStore.isBlocked(name: "ADA"))
        XCTAssertFalse(ModerationStore.isBlocked(name: "Adam"),
                       "a block must not swallow a different, longer name")
    }

    func testUnblockRestoresTheFeed() {
        let feed = [entry(id: "a", submitter: "Ada")]
        ModerationStore.block(name: "Ada")
        XCTAssertTrue(ModerationStore.filterCommunity(feed).isEmpty)
        ModerationStore.unblock(name: "ada")   // different casing on purpose
        XCTAssertEqual(ModerationStore.filterCommunity(feed).count, 1)
    }

    func testBlockingIgnoresEmptyAndAnonymousNames() {
        ModerationStore.block(name: "   ")
        XCTAssertTrue(ModerationStore.blockedNames.isEmpty)
        // An entry with no submitter must never be filtered out by a
        // block — there's no one to have blocked.
        XCTAssertFalse(ModerationStore.isBlocked(name: nil))
        XCTAssertFalse(ModerationStore.isBlocked(name: ""))
    }

    func testBlockDoesNotDuplicate() {
        ModerationStore.block(name: "Ada")
        ModerationStore.block(name: "ada")
        XCTAssertEqual(ModerationStore.blockedNames.count, 1)
    }

    func testLeaderboardHandlesAreBlockedToo() {
        let board = [StreakLeaderboardEntry(rank: 1, handle: "Ada", longestStreak: 9),
                     StreakLeaderboardEntry(rank: 2, handle: "Grace", longestStreak: 4)]
        ModerationStore.block(name: "Ada")
        XCTAssertEqual(ModerationStore.filterLeaderboard(board).map(\.handle),
                       ["Grace"])
    }

    // MARK: - Hiding and reporting

    func testHideRemovesOnlyThatEntry() {
        let feed = [entry(id: "a", submitter: "Ada"),
                    entry(id: "b", submitter: "Ada")]
        ModerationStore.hide(id: "a")
        XCTAssertEqual(ModerationStore.filterCommunity(feed).map(\.id), ["b"],
                       "hiding one puzzle must not hide the submitter's others")
    }

    /// The heart of the 1.2 contract: the content is gone from this
    /// player's feed the moment they report, with no dependency on the
    /// POST landing.
    func testReportHidesImmediatelyAndIsRemembered() {
        let feed = [entry(id: "a", submitter: "Ada")]
        ModerationStore.report(id: "a", submitterName: "Ada", reason: .offensive)
        XCTAssertTrue(ModerationStore.filterCommunity(feed).isEmpty)
        XCTAssertTrue(ModerationStore.hasReported(id: "a"))
    }

    func testReportDoesNotBlockTheSubmittersOtherPuzzles() {
        // Report and block are separate choices; reporting one puzzle
        // shouldn't silently nuke everything by that person.
        let feed = [entry(id: "a", submitter: "Ada"),
                    entry(id: "b", submitter: "Ada")]
        ModerationStore.report(id: "a", submitterName: "Ada", reason: .spam)
        XCTAssertEqual(ModerationStore.filterCommunity(feed).map(\.id), ["b"])
    }

    func testModerationStatePersistsAcrossReads() {
        ModerationStore.block(name: "Ada")
        ModerationStore.hide(id: "x")
        XCTAssertTrue(ModerationStore.blockedNames.contains("Ada"))
        XCTAssertTrue(ModerationStore.isHidden(id: "x"))
    }
}
