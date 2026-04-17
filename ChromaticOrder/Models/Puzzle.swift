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
