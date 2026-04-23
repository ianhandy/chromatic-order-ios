//  Puzzle data model — mirrors the JS puzzle object used across the
//  generator and UI.

import Foundation

enum Direction: String { case h, v }

struct GradientCellSpec: Hashable {
    var r: Int
    var c: Int
    var pos: Int           // index along the gradient (0..<len)
    var color: OKLCh       // solution color at this cell
    var locked: Bool
    var isIntersection: Bool
}

struct PuzzleGradient: Hashable {
    var id: Int
    var dir: Direction
    var len: Int
    var cells: [GradientCellSpec]
    var colors: [OKLCh]    // len elements, aligned to pos
}

// Board cell. Dead cells are untouched background slots; cell cells are
// part of a gradient and may be locked or free.
enum CellKind: String { case dead, cell }

struct BoardCell: Hashable {
    var kind: CellKind
    var solution: OKLCh?
    var placed: OKLCh?
    var locked: Bool
    var isIntersection: Bool
    var gradIds: [Int]      // which gradients pass through (mostly length 1, 2 at intersections)

    static let dead = BoardCell(kind: .dead, solution: nil, placed: nil,
                                locked: false, isIntersection: false, gradIds: [])
}

struct BankItem: Identifiable, Hashable {
    let id: Int
    let color: OKLCh
}

/// Coarse structural fingerprint of a puzzle's gradient layout.
/// Built from the sorted list of each gradient's direction + length
/// so two puzzles share a signature iff they have the same overall
/// geometry, regardless of colors, positions, or locked-cell choice.
///
/// Used by the feedback-driven generator path: when a player marks a
/// puzzle as "bad", its signature is appended to a local dislike
/// ledger, and the generator's `finalize()` consults the ledger to
/// reject candidates whose shape the player has already flagged.
enum PuzzleShape {
    /// Coarse signature — direction + length only. Used by the dislike
    /// feedback ledger where position doesn't matter.
    static func signature(of gradients: [PuzzleGradient]) -> String {
        let parts = gradients.map { "\($0.dir.rawValue)\($0.len)" }.sorted()
        return parts.joined(separator: "|")
    }

    /// Position-aware fingerprint — includes each gradient's origin
    /// cell so two puzzles with the same shape at different grid
    /// positions are considered distinct. Used for recent-dedup and
    /// solved-puzzle history.
    static func fingerprint(of gradients: [PuzzleGradient],
                            gridW: Int, gridH: Int) -> String {
        let parts = gradients.map { g -> String in
            let origin = g.cells.first.map { "\($0.r),\($0.c)" } ?? "?"
            return "\(g.dir.rawValue)\(g.len)@\(origin)"
        }.sorted()
        return "\(gridW)x\(gridH):\(parts.joined(separator: "|"))"
    }
}

struct Puzzle {
    var level: Int
    var gridW: Int
    var gridH: Int
    var board: [[BoardCell]]
    // Fixed-size bank array — one slot per unlocked cell at puzzle
    // start. Slots are `nil` when empty, which preserves the toolbox
    // grid shape as swatches are placed / moved. Drag-rearranging
    // works by moving non-nil entries between indices.
    var bank: [BankItem?]
    // The bank's size at puzzle start — matches bank.count but kept
    // as an explicit field for clarity at call sites.
    var initialBankCount: Int
    var gradients: [PuzzleGradient]
    var channelCount: Int
    var activeChannels: [Channel]
    var primaryChannel: Channel
    var difficulty: Int
    var pairProx: Double
    var extrapProx: Double
    var interDist: Double
}
