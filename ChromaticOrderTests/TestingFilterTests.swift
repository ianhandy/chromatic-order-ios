//  The test-harness filter (TestingFilter.swift + its funnels on
//  GameState). Two promises are worth pinning down here:
//
//  1. Switched off, it does nothing at all. It reaches into rendering
//     AND into the game's judging, so a leak would corrupt normal play
//     for every player, not just a tester.
//  2. A compression of `s` scales every ΔE on the board by exactly
//     (1 - s). The playtester reads its results off that identity, so
//     "roughly shrinks things" is not good enough.

import XCTest
@testable import ChromaticOrder

final class TestingFilterTests: XCTestCase {

    /// Colors spread across the usable band: light/dark, saturated/gray,
    /// and hues either side of the 0/360 seam (where naive averaging or
    /// interpolation in OKLCh goes wrong).
    private let samples: [OKLCh] = [
        OKLCh(L: 0.30, c: 0.05, h: 12),
        OKLCh(L: 0.45, c: 0.18, h: 355),
        OKLCh(L: 0.60, c: 0.22, h: 140),
        OKLCh(L: 0.72, c: 0.09, h: 220),
        OKLCh(L: 0.84, c: 0.31, h: 300),
    ]

    /// These tests run in the app host, so they write to the real app's
    /// UserDefaults. Snapshot every key they can touch and put it back,
    /// or a test run leaves the simulator's copy of the game with a
    /// compressed board, default accessibility settings, and a phantom
    /// challenge run to resume.
    private let key = "chromaticOrderTestingFilter"
    private let touchedKeys = [
        "chromaticOrderTestingFilter",
        "chromaticOrderAccessibility",
        "chromaticOrderCBMode",
        "chromaticOrderChallengeRun",
    ]
    private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        savedDefaults = [:]
        for k in touchedKeys {
            if let value = UserDefaults.standard.object(forKey: k) {
                savedDefaults[k] = value
            }
        }
    }

    override func tearDown() {
        for k in touchedKeys {
            if let value = savedDefaults[k] {
                UserDefaults.standard.set(value, forKey: k)
            } else {
                UserDefaults.standard.removeObject(forKey: k)
            }
        }
        super.tearDown()
    }

    // ─── disabled is the identity ──────────────────────────────────

    /// Every knob turned up but `enabled` false: display must hand back
    /// the exact same coordinates, and the same-color test must give the
    /// exact answers `OK.equal` gives. This is the assertion that fails
    /// if someone drops the early guard.
    func testDisabledFilterChangesNothing() {
        let off = TestingFilter(
            enabled: false, similarity: 0.9, sameThreshold: 12,
            reference: TestingFilter.meanColor(of: samples)
        )
        for color in samples {
            XCTAssertEqual(off.display(color), color,
                           "disabled filter altered \(color)")
        }
        // ΔE 5 pairs: rejected by OK.equal, and would be accepted by a
        // threshold of 12 if the guard were missing.
        for color in samples {
            let nudged = OKLCh(L: color.L + 0.05, c: color.c, h: color.h)
            XCTAssertEqual(OK.dist(color, nudged), 5, accuracy: 1e-9)
            XCTAssertFalse(off.same(color, nudged),
                           "disabled filter honoured its threshold")
            XCTAssertEqual(off.same(color, nudged),
                           OK.equal(color, nudged))
        }
        // And it still agrees with OK.equal on a genuine JND pair.
        let a = samples[2]
        let b = OKLCh(L: a.L + 0.01, c: a.c, h: a.h)
        XCTAssertTrue(off.same(a, b))
        XCTAssertEqual(off.same(a, b), OK.equal(a, b))
    }

    /// A filter with no board loaded has nothing to compress toward, so
    /// it must pass colors through rather than collapse them to some
    /// arbitrary point.
    func testMissingReferenceIsIdentity() {
        let filter = TestingFilter(enabled: true, similarity: 0.8,
                                   sameThreshold: 2, reference: nil)
        for color in samples {
            XCTAssertEqual(filter.display(color), color)
        }
    }

    // ─── compression scales every ΔE by (1 - s) ────────────────────

    /// The identity the playtester depends on, checked over every pair
    /// of the sample colors at a spread of compressions. A per-cell
    /// reference, a nonlinear pull, or compressing in sRGB would all
    /// break this.
    func testCompressionScalesEveryDeltaE() {
        let reference = TestingFilter.meanColor(of: samples)
        XCTAssertNotNil(reference)
        for similarity in [0.0, 0.1, 0.35, 0.6, 0.9, 0.95] {
            let filter = TestingFilter(enabled: true, similarity: similarity,
                                       sameThreshold: 2, reference: reference)
            for i in samples.indices {
                for j in samples.indices where j > i {
                    let before = OK.dist(samples[i], samples[j])
                    let after = OK.dist(filter.display(samples[i]),
                                        filter.display(samples[j]))
                    XCTAssertEqual(after, before * (1 - similarity), accuracy: 1e-6,
                                   "s=\(similarity) pair \(i),\(j)")
                }
            }
        }
    }

    /// Compression toward a fixed reference is what makes the sweep
    /// converge: at s = 0.95 nothing on the board can be more than 5% of
    /// its original distance from the reference away from it.
    func testCompressionConvergesOnTheReference() throws {
        let reference = try XCTUnwrap(TestingFilter.meanColor(of: samples))
        let filter = TestingFilter(enabled: true, similarity: 0.95,
                                   sameThreshold: 2, reference: reference)
        for color in samples {
            let before = OK.dist(color, reference)
            let after = OK.dist(filter.display(color), reference)
            XCTAssertEqual(after, before * 0.05, accuracy: 1e-6)
        }
    }

    /// The reference is a mean in OKLab, not in OKLCh. Two colors either
    /// side of the hue seam (355° and 5°) average to a red at 0°; a
    /// naive average of the hue ANGLES gives 180°, cyan, the opposite
    /// side of the wheel.
    func testReferenceIsTheOKLabMean() throws {
        let pair = [OKLCh(L: 0.5, c: 0.2, h: 355), OKLCh(L: 0.5, c: 0.2, h: 5)]
        let mean = try XCTUnwrap(TestingFilter.meanColor(of: pair))
        XCTAssertEqual(mean.L, 0.5, accuracy: 1e-9)
        // Red at 0°, very slightly desaturated (the two chroma vectors
        // partly cancel). Compared by ΔE rather than by hue angle, which
        // is 0 and 360 at the same time.
        let expected = OKLCh(L: 0.5, c: 0.2 * cos(5 * .pi / 180), h: 0)
        XCTAssertLessThan(OK.dist(mean, expected), 1e-6)
        // The naive average of the hue ANGLES would land here instead,
        // on the far side of the wheel.
        XCTAssertGreaterThan(OK.dist(mean, OKLCh(L: 0.5, c: mean.c, h: 180)), 10)
        XCTAssertNil(TestingFilter.meanColor(of: []))
    }

    // ─── the threshold moves what the game accepts ─────────────────

    /// A near-miss placement (ΔE 4) is accepted when the threshold sits
    /// above it and rejected when it sits below, and the wrong-cell
    /// highlighting agrees with the check in both cases, because the UI
    /// must never outline a cell the check is about to pass.
    @MainActor
    func testThresholdDecidesWhetherANearMissPasses() throws {
        // Accepted: 4 < 6.
        let lenient = try playBoardOffByFourDeltaE(enabled: true, threshold: 6)
        XCTAssertFalse(lenient.wrongCellBefore,
                       "a cell the check accepts was still marked wrong")
        XCTAssertTrue(lenient.solved)
        XCTAssertFalse(lenient.peeked, "the check should not have revealed anything")
        XCTAssertEqual(lenient.heartsLost, 0)

        // Rejected: 4 > 3.
        let strict = try playBoardOffByFourDeltaE(enabled: true, threshold: 3)
        XCTAssertTrue(strict.wrongCellBefore)
        XCTAssertTrue(strict.peeked, "the check should have rejected the board")
        XCTAssertEqual(strict.heartsLost, 1)

        // The same board with the filter switched off is judged by
        // OK.equal (ΔE 2) no matter what the threshold slider says, so a
        // stored threshold of 12 must not smuggle an acceptance through.
        let disabled = try playBoardOffByFourDeltaE(enabled: false, threshold: 12)
        XCTAssertTrue(disabled.wrongCellBefore)
        XCTAssertTrue(disabled.peeked)
        XCTAssertEqual(disabled.heartsLost, 1)
    }

    private struct CheckOutcome {
        var wrongCellBefore: Bool
        var solved: Bool
        /// Challenge's wrong-check path burns a heart and reveals the
        /// answer, so these two say "the check rejected the board"
        /// without depending on `solved`, which it sets either way.
        var peeked: Bool
        var heartsLost: Int
    }

    /// Fill campaign level 1 correctly, then push one cell off by exactly
    /// ΔE 4 (a lightness nudge of 0.04, since ΔE scales L by 100) and run
    /// the real `handleCheck`. Challenge mode so the reject path is
    /// distinguishable from the accept path.
    @MainActor
    private func playBoardOffByFourDeltaE(enabled: Bool,
                                          threshold: Double) throws -> CheckOutcome {
        let game = GameState()
        game.testingEnabled = enabled
        game.testingSimilarity = 0.6
        game.testingSameThreshold = threshold
        XCTAssertTrue(game.loadCampaignLevel(1))
        var puzzle = try XCTUnwrap(game.puzzle)

        // Write solutions in directly rather than through the bank: the
        // near-miss color isn't in the bank, and this keeps the mistake
        // counter out of the picture.
        var target: CellIndex?
        for r in 0..<puzzle.gridH {
            for c in 0..<puzzle.gridW {
                let cell = puzzle.board[r][c]
                guard cell.kind == .cell, let solution = cell.solution else { continue }
                puzzle.board[r][c].placed = solution
                if !cell.locked, target == nil { target = CellIndex(r: r, c: c) }
            }
        }
        let idx = try XCTUnwrap(target, "level 1 has no free cell")
        let solution = try XCTUnwrap(puzzle.board[idx.r][idx.c].solution)
        let nearMiss = OKLCh(L: solution.L + 0.04, c: solution.c, h: solution.h)
        XCTAssertEqual(OK.dist(solution, nearMiss), 4, accuracy: 1e-9)
        puzzle.board[idx.r][idx.c].placed = nearMiss
        puzzle.bank = Array(repeating: nil, count: puzzle.bank.count)
        game.puzzle = puzzle

        // Challenge with hearts to spend: a rejected check costs one.
        game.mode = .challenge
        game.checks = 3
        game.showIncorrect = true
        let wrongCellBefore = game.hasAnyWrongCell
        game.handleCheck()

        return CheckOutcome(
            wrongCellBefore: wrongCellBefore,
            solved: game.solved,
            peeked: game.showedIncorrect,
            heartsLost: 3 - game.checks
        )
    }

    // ─── persistence ───────────────────────────────────────────────

    /// The knobs survive a relaunch. `applyAccessibilityIfChanged` is
    /// the sheet's own close hook, so this exercises the real save path
    /// rather than a private one.
    @MainActor
    func testSettingsRoundTripThroughUserDefaults() {
        let game = GameState()
        game.testingEnabled = true
        game.testingSimilarity = 0.75
        game.testingSameThreshold = 8.5
        game.applyAccessibilityIfChanged()

        let reloaded = GameState()
        XCTAssertTrue(reloaded.testingEnabled)
        XCTAssertEqual(reloaded.testingSimilarity, 0.75, accuracy: 1e-9)
        XCTAssertEqual(reloaded.testingSameThreshold, 8.5, accuracy: 1e-9)

        // Reset clears them too, and that also persists.
        reloaded.resetAccessibility()
        let afterReset = GameState()
        XCTAssertFalse(afterReset.testingEnabled)
        XCTAssertEqual(afterReset.testingSimilarity,
                       GameState.testingDefaults.similarity, accuracy: 1e-9)
        XCTAssertEqual(afterReset.testingSameThreshold,
                       GameState.testingDefaults.sameThreshold, accuracy: 1e-9)
    }

    /// A fresh install has the filter off, so the display funnel is a
    /// pass-through and the judging funnel matches `OK.equal` on a board
    /// that is actually loaded.
    @MainActor
    func testGameStateDefaultsToNoFiltering() {
        UserDefaults.standard.removeObject(forKey: key)
        let game = GameState()
        XCTAssertFalse(game.testingEnabled)
        XCTAssertTrue(game.loadCampaignLevel(1))
        XCTAssertNotNil(game.testingReference,
                        "the reference is computed per board load, filter or not")
        for color in samples {
            XCTAssertEqual(game.display(color), color)
            let nudged = OKLCh(L: color.L + 0.05, c: color.c, h: color.h)
            XCTAssertEqual(game.sameColor(color, nudged), OK.equal(color, nudged))
        }
    }

    /// With the filter on, the reference is the mean of THIS board's
    /// solution colors, the property that makes the compression
    /// converge instead of chasing a moving target.
    @MainActor
    func testReferenceComesFromTheLoadedBoard() throws {
        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(1))
        let puzzle = try XCTUnwrap(game.puzzle)
        var solutions: [OKLCh] = []
        for r in 0..<puzzle.gridH {
            for c in 0..<puzzle.gridW where puzzle.board[r][c].kind == .cell {
                if let sol = puzzle.board[r][c].solution { solutions.append(sol) }
            }
        }
        let expected = try XCTUnwrap(TestingFilter.meanColor(of: solutions))
        XCTAssertEqual(try XCTUnwrap(game.testingReference), expected)

        // A different board must move it.
        XCTAssertTrue(game.loadCampaignLevel(2))
        XCTAssertNotEqual(try XCTUnwrap(game.testingReference), expected)
    }
}
