//  The puzzle grid. Each cell is a CellView with drag/tap handling.
//  cellPx is computed from the available frame so the whole grid
//  always fits — never scrolls.

import SwiftUI

struct GridView: View {
    @Bindable var game: GameState

    var body: some View {
        GeometryReader { geo in
            Group {
                if let p = game.puzzle {
                    gridBody(p: p, size: geo.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gridBody(p: Puzzle, size: CGSize) -> some View {
        let b = usedBounds(p)
        let rows = max(1, b.maxR - b.minR + 1)
        let cols = max(1, b.maxC - b.minC + 1)
        let margin: CGFloat = 2
        let padding: CGFloat = 12
        let availW = max(0, size.width - padding * 2)
        let availH = max(0, size.height - padding * 2)
        let perW = (availW / CGFloat(cols)) - margin * 2
        let perH = (availH / CGFloat(rows)) - margin * 2
        let cellPx = max(10, min(64, min(perW, perH)))

        return VStack(spacing: 0) {
            ForEach(b.minR...b.maxR, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(b.minC...b.maxC, id: \.self) { c in
                        CellView(
                            r: r, c: c,
                            cell: p.board[r][c],
                            cellPx: cellPx,
                            game: game
                        )
                        .frame(width: cellPx + margin * 2,
                               height: cellPx + margin * 2)
                    }
                }
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(CellFramesKey.self) { frames in
            Task { @MainActor in game.cellFrames = frames }
        }
    }

    private func usedBounds(_ p: Puzzle) -> (minR: Int, maxR: Int, minC: Int, maxC: Int) {
        var minR = p.gridH, maxR = 0, minC = p.gridW, maxC = 0
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                if r < minR { minR = r }; if r > maxR { maxR = r }
                if c < minC { minC = c }; if c > maxC { maxC = c }
            }
        }
        if minR > maxR { minR = 0; maxR = 0 }
        if minC > maxC { minC = 0; maxC = 0 }
        return (minR, maxR, minC, maxC)
    }
}
