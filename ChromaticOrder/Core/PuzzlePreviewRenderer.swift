//  Rasterizes a Puzzle to a shareable PNG. Draws directly via
//  UIGraphicsImageRenderer rather than bouncing through SwiftUI's
//  ImageRenderer — the latter's interaction with the rendered view's
//  implicit layout pass (esp. GeometryReader) was producing nil /
//  blank images in the share sheet. Direct Core Graphics drawing is
//  deterministic and side-steps the issue entirely.

import SwiftUI
import UIKit

enum PuzzlePreviewRenderer {
    /// Render the puzzle's starting state to an Image — locked cells
    /// show their solution color, free cells show as faint slots,
    /// dead cells as transparent. Returns nil only if the bitmap
    /// renderer itself fails (vanishingly rare).
    @MainActor
    static func render(_ puzzle: Puzzle) -> Image? {
        guard let ui = renderUIImage(puzzle) else { return nil }
        return Image(uiImage: ui)
    }

    /// Same as `render` but returns UIImage directly. Handy for any
    /// call site that needs the UIImage rather than SwiftUI's Image
    /// wrapper.
    @MainActor
    static func renderUIImage(_ puzzle: Puzzle) -> UIImage? {
        let b = usedBounds(puzzle)
        let rows = max(1, b.maxR - b.minR + 1)
        let cols = max(1, b.maxC - b.minC + 1)

        let cellPx: CGFloat = 56
        let spacing: CGFloat = 3
        let padding: CGFloat = 48
        let cornerRadius: CGFloat = 10

        let width = CGFloat(cols) * cellPx
            + CGFloat(max(0, cols - 1)) * spacing
            + padding * 2
        let height = CGFloat(rows) * cellPx
            + CGFloat(max(0, rows - 1)) * spacing
            + padding * 2

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )

        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let emptyFill = UIColor.white.withAlphaComponent(0.14)
            for r in b.minR...b.maxR {
                for c in b.minC...b.maxC {
                    let cell = puzzle.board[r][c]
                    guard cell.kind == .cell else { continue }
                    let x = padding + CGFloat(c - b.minC) * (cellPx + spacing)
                    let y = padding + CGFloat(r - b.minR) * (cellPx + spacing)
                    let rect = CGRect(x: x, y: y, width: cellPx, height: cellPx)
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
                    if cell.locked, let color = cell.solution {
                        UIColor(OK.toColor(color)).setFill()
                    } else {
                        emptyFill.setFill()
                    }
                    path.fill()
                }
            }
        }
    }

    /// Trim to the used rectangle so the image isn't padded out by
    /// empty dead-cell rows/columns around the real layout.
    private static func usedBounds(_ p: Puzzle) -> (minR: Int, maxR: Int, minC: Int, maxC: Int) {
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
