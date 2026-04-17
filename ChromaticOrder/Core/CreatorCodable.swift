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
}
