//  Seeded generation has to be reproducible: the daily's offline fallback
//  and the first-run tutorial layouts both assume that seed + level decide
//  the board. That assumption used to be false above level ~5, because the
//  builder iterated Dictionaries whose order Swift randomises per instance —
//  a fixed RNG stream then shuffled a differently-ordered array each run.
//
//  These tests are the guard against that class of bug coming back: any new
//  unordered iteration in the build path will show up here as a diverging
//  board rather than as a mysterious "the daily isn't the same for everyone".

import XCTest


final class GeneratorDeterminismTests: XCTestCase {

    private func fingerprint(level: Int, seed: UInt64, deterministic: Bool) -> String {
        var config = GenConfig()
        config.deterministic = deterministic
        let rng = SeededRNGRef(seed: seed)
        let puzzle = GenRNG.$current.withValue(rng) {
            generatePuzzle(level: level, config: config)
        }
        return PuzzleShape.fingerprint(of: puzzle.gradients,
                                       gridW: puzzle.gridW, gridH: puzzle.gridH)
    }

    /// The RNG stream itself, straight through Util — the floor everything
    /// else stands on.
    func testSeededStreamAndUtilAreStable() {
        func raw() -> [UInt64] {
            let rng = SeededRNGRef(seed: 0xDEADBEEF)
            return GenRNG.$current.withValue(rng) {
                (0..<16).map { _ in GenRNG.with { $0.next() } }
            }
        }
        XCTAssertEqual(raw(), raw())

        func viaUtil() -> [Double] {
            let rng = SeededRNGRef(seed: 42)
            return GenRNG.$current.withValue(rng) {
                (0..<16).map { _ in Util.randRange(0, 1) }
            }
        }
        XCTAssertEqual(viaUtil(), viaUtil())
    }

    /// One build attempt, same seed, same board — across the whole level
    /// range, including the high levels where the builder branches most and
    /// where the unordered-iteration bug used to bite.
    func testSingleBuildAttemptIsReproducible() {
        for level in [1, 5, 10, 14, 18, 21] {
            var prints: Set<String> = []
            for _ in 0..<3 {
                let rng = SeededRNGRef(seed: 0xC0FFEE)
                let puzzle = GenRNG.$current.withValue(rng) {
                    tryGrowOnce(level: level, config: GenConfig())
                }
                prints.insert(puzzle.map {
                    PuzzleShape.fingerprint(of: $0.gradients,
                                            gridW: $0.gridW, gridH: $0.gridH)
                } ?? "nil")
            }
            XCTAssertEqual(prints.count, 1,
                           "level \(level): one seed produced \(prints.count) different builds")
        }
    }

    /// Full generation in reproducible mode: same seed, same board, even
    /// with unrelated generation dirtying the stash and seen-shape ledgers
    /// in between.
    func testFullGenerationIsReproducibleInDeterministicMode() {
        for level in [1, 10, 14, 20] {
            let first = fingerprint(level: level, seed: 0xABCDEF, deterministic: true)
            _ = generatePuzzle(level: 12, config: GenConfig())   // dirty the state
            _ = generatePuzzle(level: 7, config: GenConfig())
            let second = fingerprint(level: level, seed: 0xABCDEF, deterministic: true)
            XCTAssertEqual(first, second, "level \(level) diverged between runs")
        }
    }

    /// Different seeds still have to give different boards — determinism
    /// mustn't collapse into "one board per level".
    func testDifferentSeedsGiveDifferentBoards() {
        let a = fingerprint(level: 14, seed: 1, deterministic: true)
        let b = fingerprint(level: 14, seed: 2, deterministic: true)
        XCTAssertNotEqual(a, b)
    }

    /// Reproducible mode must leave the per-install ledgers untouched —
    /// that's what makes it reproducible, and it also means a daily
    /// fallback can't consume a stashed puzzle intended for zen.
    func testDeterministicModeLeavesTheStashAlone() {
        // Drain the bucket, drop in a marker, generate, and check the marker
        // is still sitting there untouched.
        while StashedPuzzleStore.pop(difficulty: 10) != nil {}
        let marker = "{\"marker\":\"determinism-test\"}"
        StashedPuzzleStore.stash(puzzleJSON: marker, difficulty: 10)
        _ = fingerprint(level: 20, seed: 0x5EED, deterministic: true)
        XCTAssertEqual(StashedPuzzleStore.pop(difficulty: 10), marker,
                       "reproducible generation read or wrote the stash")
    }
}
