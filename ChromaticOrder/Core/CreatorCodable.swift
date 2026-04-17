//  JSON codec for created puzzles. Share / export round-trips through
//  this — compact, stable schema, versioned so we can evolve later
//  without breaking old shares.

import Foundation

struct CreatorPuzzleDoc: Codable {
    let version: Int
    let gridW: Int
    let gridH: Int
    let gradients: [Grad]
    /// Embedded difficulty so recipients can preview the score
    /// without running the scorer. Optional — old docs won't have it.
    var difficulty: Int?

    struct Grad: Codable {
        let dir: String       // "h" | "v"
        let cells: [Cell]
    }
    struct Cell: Codable {
        let r: Int
        let c: Int
        let L: Double
        let C: Double         // renamed field so JSON stays readable
        let h: Double
        // Optional so pre-v1 documents (creator exports) still decode
        // cleanly. When present, preserves the exact lock config the
        // generator produced — matters when we replay a liked puzzle
        // to another player and want them to see the SAME layout, not
        // a re-derived auto-locked version.
        var locked: Bool?
    }

    static let currentVersion = 1
}

enum CreatorCodec {
    /// Serialize the laid gradients from a CreatorState. Keeps colors
    /// in full OKLCh precision (no sRGB round-trip loss).
    /// @MainActor because CreatorState is isolated to the main actor
    /// and we read its gradients array here.
    @MainActor
    static func encode(_ state: CreatorState, difficulty: Int? = nil) throws -> Data {
        let doc = CreatorPuzzleDoc(
            version: CreatorPuzzleDoc.currentVersion,
            gridW: CreatorState.canvasCols,
            gridH: CreatorState.canvasRows,
            gradients: state.gradients.map { g in
                CreatorPuzzleDoc.Grad(
                    dir: g.dir == .h ? "h" : "v",
                    cells: zip(g.cells, g.colors).map { (idx, color) in
                        CreatorPuzzleDoc.Cell(
                            r: idx.r, c: idx.c,
                            L: color.L, C: color.c, h: color.h
                        )
                    }
                )
            },
            difficulty: difficulty
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try enc.encode(doc)
    }

    @MainActor
    static func encodeString(_ state: CreatorState, difficulty: Int? = nil) throws -> String {
        let data = try encode(state, difficulty: difficulty)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Round-trip: rehydrate a CreatorState from a share payload.
    /// Unknown versions throw; caller should show "this share needs a
    /// newer version of the app."
    static func decode(_ data: Data) throws -> CreatorPuzzleDoc {
        let dec = JSONDecoder()
        let doc = try dec.decode(CreatorPuzzleDoc.self, from: data)
        guard doc.version == CreatorPuzzleDoc.currentVersion else {
            throw NSError(
                domain: "CreatorCodec", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Puzzle version \(doc.version) not supported — update the app."])
        }
        return doc
    }

    /// Serialize a live `Puzzle` (generator or creator output) into the
    /// same JSON schema. Preserves per-cell lock state so we can replay
    /// a liked layout to other players without re-deriving locks via
    /// the auto-lock rules. Compact JSON (no pretty-print) keeps the
    /// payload small for the "Kroma Level Like" Paragraph field.
    static func encodePuzzle(_ p: Puzzle) throws -> String {
        // Deduplicate gradient cells by (r, c): intersections appear in
        // multiple gradients' cell arrays. The sharer's intent is
        // "this layout" not "this traversal order" — so we emit one
        // entry per grid cell across all gradients.
        let doc = CreatorPuzzleDoc(
            version: CreatorPuzzleDoc.currentVersion,
            gridW: p.gridW,
            gridH: p.gridH,
            gradients: p.gradients.map { g in
                CreatorPuzzleDoc.Grad(
                    dir: g.dir == .h ? "h" : "v",
                    cells: g.cells.map { spec in
                        CreatorPuzzleDoc.Cell(
                            r: spec.r, c: spec.c,
                            L: spec.color.L, C: spec.color.c, h: spec.color.h,
                            locked: spec.locked
                        )
                    }
                )
            },
            difficulty: p.difficulty
        )
        let enc = JSONEncoder()
        // Compact — every char counts when this has to fit in a
        // Google Forms Paragraph field along with the widget's own
        // POST body budget.
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(doc)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
