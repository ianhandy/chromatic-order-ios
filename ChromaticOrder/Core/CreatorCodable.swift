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
    /// Session context — present when the doc was generated from a
    /// live play session (like-widget submissions). Absent when the
    /// doc is a pure puzzle share (creator export). All optional so
    /// old docs still decode; when populated, lets us attribute a
    /// report to its play context (what level was it rated at? was
    /// the player in challenge mode? was CB simulation on?).
    var level: Int?
    var mode: String?
    var cbMode: String?

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

    /// Rehydrate a `CreatorPuzzleDoc` into a playable `Puzzle`. Used
    /// by the .kroma file handler (ChromaticOrderApp.onOpenURL) to
    /// turn a shared file back into something GameState can load.
    /// Lock state comes from each cell's `locked` field (optional so
    /// pre-v1-locked docs still decode; absent == no lock).
    static func rebuild(_ doc: CreatorPuzzleDoc, level: Int = 1) -> Puzzle? {
        // Build PuzzleGradient structs in local (already-local) coords.
        // Track per-cell ownership so we can flag intersections; bank
        // collection dedupes on (r, c) because a shared intersection
        // lives in two gradients' cell arrays.
        var outGrads: [PuzzleGradient] = []
        var ownersByCell: [CellIndex: [Int]] = [:]
        for (gi, grad) in doc.gradients.enumerated() {
            for cell in grad.cells {
                ownersByCell[CellIndex(r: cell.r, c: cell.c), default: []].append(gi)
            }
        }
        for (gi, grad) in doc.gradients.enumerated() {
            let dir: Direction = grad.dir == "v" ? .v : .h
            var specs: [GradientCellSpec] = []
            var colors: [OKLCh] = []
            for (i, cell) in grad.cells.enumerated() {
                let color = OKLCh(L: cell.L, c: cell.C, h: cell.h)
                let idx = CellIndex(r: cell.r, c: cell.c)
                let isIntersection = (ownersByCell[idx]?.count ?? 0) >= 2
                specs.append(GradientCellSpec(
                    r: cell.r, c: cell.c, pos: i, color: color,
                    locked: cell.locked ?? false,
                    isIntersection: isIntersection
                ))
                colors.append(color)
            }
            outGrads.append(PuzzleGradient(
                id: gi, dir: dir, len: grad.cells.count,
                cells: specs, colors: colors))
        }

        // Board grid — dead everywhere except the gradient cells.
        var board: [[BoardCell]] = Array(
            repeating: Array(repeating: .dead, count: doc.gridW),
            count: doc.gridH)
        for g in outGrads {
            for spec in g.cells {
                if board[spec.r][spec.c].kind == .dead {
                    board[spec.r][spec.c] = BoardCell(
                        kind: .cell,
                        solution: spec.color,
                        placed: spec.locked ? spec.color : nil,
                        locked: spec.locked,
                        isIntersection: spec.isIntersection,
                        gradIds: [g.id])
                } else {
                    var cell = board[spec.r][spec.c]
                    cell.isIntersection = true
                    if !cell.gradIds.contains(g.id) { cell.gradIds.append(g.id) }
                    if spec.locked {
                        cell.locked = true
                        cell.placed = spec.color
                    }
                    board[spec.r][spec.c] = cell
                }
            }
        }

        // Bank = distinct unlocked solution colors.
        var bank: [BankItem] = []
        var seen: Set<CellIndex> = []
        var uid = 0
        for g in outGrads {
            for spec in g.cells where !spec.locked {
                let key = CellIndex(r: spec.r, c: spec.c)
                if seen.insert(key).inserted {
                    bank.append(BankItem(id: uid, color: spec.color)); uid += 1
                }
            }
        }
        bank.shuffle()

        // Gate: every gradient must have at least one free cell.
        guard outGrads.allSatisfy({ g in g.cells.contains(where: { !$0.locked }) }) else {
            return nil
        }

        // Active channels + primary for scoring + UI. Infer from per-
        // step deltas the same way CreatorBuilder does — gives us
        // consistent behavior between authored and imported puzzles.
        let (channels, primary) = inferChannelsAndPrimaryForDoc(outGrads)
        let pairProx = cellPairProximityScore(outGrads)
        let extrapProx = extrapolationProximityScore(outGrads)
        let lineProx = minInterGradientLineDist(outGrads.map { $0.colors })
        let difficulty = doc.difficulty ?? scoreDifficulty(
            gradients: outGrads,
            bankCount: bank.count,
            channelCount: channels.count,
            primary: primary,
            pairProx: pairProx,
            extrapProx: extrapProx)

        return Puzzle(
            level: level,
            gridW: doc.gridW, gridH: doc.gridH,
            board: board,
            bank: bank.map { Optional($0) },
            initialBankCount: bank.count,
            gradients: outGrads,
            channelCount: channels.count,
            activeChannels: channels,
            primaryChannel: primary,
            difficulty: difficulty,
            pairProx: pairProx,
            extrapProx: extrapProx,
            interDist: lineProx)
    }

    /// Duplicate of CreatorBuilder's private inference — kept standalone
    /// so the decoder doesn't pull in the whole builder. Small enough
    /// that the redundancy is cheaper than a refactor.
    private static func inferChannelsAndPrimaryForDoc(_ gradients: [PuzzleGradient]) -> ([Channel], Channel) {
        var avgAbs: [Channel: Double] = [.L: 0, .c: 0, .h: 0]
        var n = 0
        for g in gradients where g.colors.count >= 2 {
            for i in 1..<g.colors.count {
                let a = g.colors[i - 1], b = g.colors[i]
                avgAbs[.L, default: 0] += abs(b.L - a.L)
                avgAbs[.c, default: 0] += abs(b.c - a.c)
                var dh = b.h - a.h
                if dh > 180 { dh -= 360 }
                if dh < -180 { dh += 360 }
                avgAbs[.h, default: 0] += abs(dh) / 180
                n += 1
            }
        }
        if n > 0 { for k in avgAbs.keys { avgAbs[k]! /= Double(n) } }
        let active = Channel.allCases.filter { (avgAbs[$0] ?? 0) > 1e-4 }
        let sorted = active.sorted { (avgAbs[$0] ?? 0) > (avgAbs[$1] ?? 0) }
        return (active.isEmpty ? [.h] : active, sorted.first ?? .h)
    }

    /// Serialize a live Puzzle + its session context (level the player
    /// was at, game mode, CB mode) into one JSON blob. Everything the
    /// Like-widget form needs lives here — no need for a sheet schema
    /// with nine redundant columns when the structure can be derived
    /// on read. Pass `level/mode/cbMode` nil for creator-export paths
    /// that don't have a session.
    static func encodePuzzleWithSession(
        _ p: Puzzle,
        level: Int? = nil,
        mode: String? = nil,
        cbMode: String? = nil
    ) throws -> String {
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
            difficulty: p.difficulty,
            level: level,
            mode: mode,
            cbMode: cbMode
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(doc)
        return String(data: data, encoding: .utf8) ?? ""
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
