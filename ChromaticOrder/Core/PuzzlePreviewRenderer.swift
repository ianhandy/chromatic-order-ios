//  Rasterizes a Puzzle to a shareable PNG via SwiftUI's ImageRenderer.
//  Used by the Share flow so the recipient sees what the level looks
//  like (in its uncompleted, clues-only state) rather than a generic
//  app icon — massively improves "should I tap this?" signal.

import SwiftUI

enum PuzzlePreviewRenderer {
    /// Render the puzzle's starting state — locked cells show their
    /// color, free cells show as pale empty slots, dead cells as
    /// transparent. Returns nil if the renderer couldn't produce a
    /// UIImage (should never happen, but the API is optional).
    @MainActor
    static func render(_ puzzle: Puzzle) -> Image? {
        let view = PreviewBoard(puzzle: puzzle)
            .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

private struct PreviewBoard: View {
    let puzzle: Puzzle

    var body: some View {
        GeometryReader { geo in
            let b = usedBounds(puzzle)
            let rows = max(1, b.maxR - b.minR + 1)
            let cols = max(1, b.maxC - b.minC + 1)
            let margin: CGFloat = 4
            // Fit the board inside the canvas with generous padding so
            // the preview thumbnail has breathing room.
            let pad: CGFloat = geo.size.width * 0.08
            let availW = geo.size.width - pad * 2
            let availH = geo.size.height - pad * 2
            let cellPx = min(
                availW / CGFloat(cols) - margin * 2,
                availH / CGFloat(rows) - margin * 2
            )
            let radius = cellPx * 0.22

            ZStack {
                Color.black
                VStack(spacing: 0) {
                    ForEach(b.minR...b.maxR, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(b.minC...b.maxC, id: \.self) { c in
                                cellView(puzzle.board[r][c], cellPx: cellPx, radius: radius)
                                    .frame(
                                        width: cellPx + margin * 2,
                                        height: cellPx + margin * 2
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: BoardCell, cellPx: CGFloat, radius: CGFloat) -> some View {
        if cell.kind == .dead {
            Color.clear
        } else if cell.locked, let color = cell.solution {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(OK.toColor(color))
                .frame(width: cellPx, height: cellPx)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(width: cellPx, height: cellPx)
        }
    }

    /// Trim the used rectangle so the preview isn't padded out by
    /// empty dead-cell rows/columns around the real layout.
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
