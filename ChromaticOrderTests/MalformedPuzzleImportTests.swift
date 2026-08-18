//  Hostile-input tests for the puzzle import path.
//
//  `CreatorCodec.rebuild` turns a decoded `CreatorPuzzleDoc` into a
//  playable board by allocating `gridH × gridW` and then writing each
//  gradient cell at `board[r][c]`. Every one of those four numbers
//  arrives from outside the app:
//
//    • a `.kroma` file tapped in Mail / Messages / Files / AirDrop
//    • a `kroma://play?data=<base64url>` link anyone can send
//    • a universal link resolved through /api/share
//    • the daily puzzle and community pool, straight off the server
//
//  `CreatorCodec.decode` only gates on `version`, so before the guard
//  these tests cover, a doc could name a negative grid (Array(repeating:
//  count: -1) traps), or place a cell outside the grid it declared
//  (Index out of range). One crafted link was a deterministic crash.
//
//  These assert the decode/rebuild pair REJECTS such a doc rather than
//  trapping. Every `rebuild` call site already handles nil, so
//  rejection degrades to "nothing opens" instead of a crash.

import XCTest
@testable import ChromaticOrder

final class MalformedPuzzleImportTests: XCTestCase {

    /// Build a doc JSON with a single horizontal gradient whose two
    /// cells sit at the given coordinates.
    private func docJSON(gridW: Int, gridH: Int,
                         cells: [(r: Int, c: Int)]) -> Data {
        let cellObjs = cells.map { cell in
            """
            {"r":\(cell.r),"c":\(cell.c),"L":0.6,"C":0.1,"h":30,\
            "locked":false,"isIntersection":false}
            """
        }.joined(separator: ",")
        return Data("""
        {"version":1,"gridW":\(gridW),"gridH":\(gridH),
         "gradients":[{"id":0,"dir":"h","cells":[\(cellObjs)]}]}
        """.utf8)
    }

    /// Rebuild must refuse a doc rather than trap. Returns the result so
    /// callers can assert nil; a trap fails the test by crashing the run.
    private func rebuilt(_ data: Data) -> Puzzle? {
        guard let doc = try? CreatorCodec.decode(data) else { return nil }
        return CreatorCodec.rebuild(doc, level: 1)
    }

    // MARK: - Negative / zero dimensions

    func testNegativeGridWidthIsRejected() {
        // Array(repeating:count:) traps on a negative count.
        XCTAssertNil(rebuilt(docJSON(gridW: -1, gridH: 4,
                                     cells: [(0, 0), (0, 1)])))
    }

    func testNegativeGridHeightIsRejected() {
        XCTAssertNil(rebuilt(docJSON(gridW: 4, gridH: -3,
                                     cells: [(0, 0), (0, 1)])))
    }

    func testZeroSizedGridIsRejected() {
        // Decodes and rebuilds "successfully" into an empty board, which
        // then crashes GridView/PuzzlePreviewRenderer downstream when
        // they subscript board[0][0]. Reject at the door instead.
        XCTAssertNil(rebuilt(Data("""
        {"version":1,"gridW":0,"gridH":0,"gradients":[]}
        """.utf8)))
    }

    // MARK: - Out-of-range cell coordinates

    func testCellRowBeyondGridHeightIsRejected() {
        XCTAssertNil(rebuilt(docJSON(gridW: 4, gridH: 4,
                                     cells: [(0, 0), (40, 0)])))
    }

    func testCellColumnBeyondGridWidthIsRejected() {
        XCTAssertNil(rebuilt(docJSON(gridW: 4, gridH: 4,
                                     cells: [(0, 0), (0, 99)])))
    }

    func testNegativeCellCoordinatesAreRejected() {
        XCTAssertNil(rebuilt(docJSON(gridW: 4, gridH: 4,
                                     cells: [(-1, 0), (0, 1)])))
        XCTAssertNil(rebuilt(docJSON(gridW: 4, gridH: 4,
                                     cells: [(0, -1), (0, 1)])))
    }

    // MARK: - Absurd dimensions

    func testAbsurdlyLargeGridIsRejected() {
        // Not a trap, but a multi-gigabyte allocation and an unplayable
        // board. The generator caps itself at 20x20 (Generate.swift);
        // the decoder should be in the same neighborhood.
        XCTAssertNil(rebuilt(docJSON(gridW: 100_000, gridH: 100_000,
                                     cells: [(0, 0), (0, 1)])))
    }

    // MARK: - Negative control: a well-formed doc still works

    func testWellFormedDocStillRebuilds() {
        let puzzle = rebuilt(docJSON(gridW: 3, gridH: 1,
                                     cells: [(0, 0), (0, 1), (0, 2)]))
        let unwrapped = try? XCTUnwrap(puzzle)
        XCTAssertNotNil(unwrapped,
                        "validation must not reject legitimate puzzles")
        if let p = unwrapped {
            XCTAssertEqual(p.board.count, 1)
            XCTAssertEqual(p.board[0].count, 3)
        }
    }

    /// The version gate is the only pre-existing guard; make sure adding
    /// dimension validation didn't displace it.
    func testUnsupportedVersionStillThrows() {
        let data = Data("""
        {"version":99,"gridW":3,"gridH":1,"gradients":[]}
        """.utf8)
        XCTAssertThrowsError(try CreatorCodec.decode(data))
    }
}
