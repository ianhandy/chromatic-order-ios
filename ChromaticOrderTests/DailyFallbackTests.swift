//  The daily's local fallback. When the server has nothing published for a
//  date (or the player is offline), generation falls through to the local
//  generator seeded off the UTC date. The promise that makes that
//  acceptable is determinism: same date + same build = same board for
//  everyone. These tests pin that promise down.

import XCTest
@testable import ChromaticOrder

final class DailyFallbackTests: XCTestCase {

    /// Same date key must hash to the same seed, and different dates must
    /// not collide — otherwise consecutive days would repeat a puzzle.
    func testDateSeedIsStableAndDistinct() {
        XCTAssertEqual(Daily.seed(for: "2026-08-12"), Daily.seed(for: "2026-08-12"))
        var seen: Set<UInt64> = []
        for day in 1...28 {
            let key = String(format: "2026-08-%02d", day)
            XCTAssertTrue(seen.insert(Daily.seed(for: key)).inserted,
                          "\(key) collides with an earlier day's seed")
        }
    }

    /// The generator, given the date seed, produces the identical board
    /// twice — this is what makes the offline daily the same puzzle for
    /// every player rather than a private random one.
    func testSeededGenerationIsReproducible() throws {
        let key = "2026-08-12"
        let level = Daily.level(for: key)
        var config = GenConfig()
        // What GameState sets for the fallback. Without it the generator is
        // path-dependent on the stash + seen-shape ledgers and the same seed
        // yields different boards.
        config.deterministic = true

        func build() throws -> Puzzle {
            let rng = SeededRNGRef(seed: Daily.seed(for: key))
            let puzzle = GenRNG.$current.withValue(rng) {
                generatePuzzle(level: level, config: config)
            }
            return try XCTUnwrap(puzzle, "seeded generation returned nothing")
        }

        let first = try build()
        // Generate an unrelated board in between: it dirties the stash and
        // the recent-shape ledger, which is exactly the state that used to
        // make the second run diverge.
        _ = generatePuzzle(level: 12, config: GenConfig())
        let second = try build()

        XCTAssertEqual(first.gridW, second.gridW)
        XCTAssertEqual(first.gridH, second.gridH)
        XCTAssertEqual(first.gradients.count, second.gradients.count)
        for (a, b) in zip(first.gradients, second.gradients) {
            XCTAssertEqual(a.dir, b.dir)
            XCTAssertEqual(a.cells.count, b.cells.count)
            for (specA, specB) in zip(a.cells, b.cells) {
                XCTAssertEqual(specA.r, specB.r)
                XCTAssertEqual(specA.c, specB.c)
                XCTAssertEqual(specA.locked, specB.locked)
                XCTAssertLessThan(OK.dist(specA.color, specB.color), 0.001,
                                  "same seed produced a different colour")
            }
        }

        // And the board it produces is actually solvable, since this is now
        // a board real players can be handed.
        XCTAssertTrue(PuzzleSolver.isUniquelySolvable(first),
                      "the date-seeded fallback board must be uniquely solvable")
    }

    /// Two different days must not hand out the same board.
    func testDifferentDaysDifferentBoards() throws {
        func fingerprint(_ key: String) throws -> String {
            var config = GenConfig()
            config.deterministic = true
            let rng = SeededRNGRef(seed: Daily.seed(for: key))
            let puzzle = try XCTUnwrap(GenRNG.$current.withValue(rng) {
                generatePuzzle(level: Daily.level(for: key), config: config)
            })
            return PuzzleShape.fingerprint(of: puzzle.gradients,
                                           gridW: puzzle.gridW,
                                           gridH: puzzle.gridH)
        }
        let a = try fingerprint("2026-08-12")
        let b = try fingerprint("2026-08-13")
        XCTAssertNotEqual(a, b, "consecutive days produced the same layout")
    }
}
