//  Rasterizes a solved puzzle to a shareable PNG. The view draws a
//  clean static grid — no drag handles, no bank, no overlays — with
//  a 50%-opacity black frame around the puzzle and a tiny lowercase
//  "kromatika" watermark pinned to the bottom-right corner. Rendered
//  at 2x scale for Retina output even when invoked from code
//  (ImageRenderer's default is 1x).

import SwiftUI
import UIKit

@MainActor
enum SolvedShareImage {
    /// Render the puzzle's solution grid to a UIImage. Returns nil on
    /// the rare occasion ImageRenderer fails to produce a CGImage.
    static func render(puzzle: Puzzle) -> UIImage? {
        let renderer = ImageRenderer(content: SolvedGridSnapshot(puzzle: puzzle))
        // 2x regardless of screen scale — consistent output quality
        // across devices without depending on UIScreen.
        renderer.scale = 2.0
        return renderer.uiImage
    }
}

private struct SolvedGridSnapshot: View {
    let puzzle: Puzzle

    private static let cellPx: CGFloat = 56
    private static let spacing: CGFloat = 3
    /// Thickness of the 50%-opacity black frame around the grid.
    private static let border: CGFloat = 44
    /// Inner padding between the border and the grid itself.
    private static let innerPad: CGFloat = 24

    var body: some View {
        let b = usedBounds(puzzle)
        let rows = max(1, b.maxR - b.minR + 1)
        let cols = max(1, b.maxC - b.minC + 1)
        let gridW = CGFloat(cols) * Self.cellPx
            + CGFloat(max(0, cols - 1)) * Self.spacing
        let gridH = CGFloat(rows) * Self.cellPx
            + CGFloat(max(0, rows - 1)) * Self.spacing
        let innerW = gridW + Self.innerPad * 2
        let innerH = gridH + Self.innerPad * 2
        let totalW = innerW + Self.border * 2
        let totalH = innerH + Self.border * 2

        ZStack(alignment: .bottomTrailing) {
            // 50%-opacity black frame: a black fill behind the
            // whole image that peeks out through the border strip
            // on all four sides.
            Color.black.opacity(0.5)
                .frame(width: totalW, height: totalH)

            // Inner puzzle area — solid black so the grid has a
            // dark stage to sit on.
            VStack(spacing: Self.spacing) {
                ForEach(b.minR...b.maxR, id: \.self) { r in
                    HStack(spacing: Self.spacing) {
                        ForEach(b.minC...b.maxC, id: \.self) { c in
                            cellSquare(at: r, c)
                        }
                    }
                }
            }
            .padding(Self.innerPad)
            .frame(width: innerW, height: innerH)
            .background(Color.black)
            .padding(Self.border)

            // Watermark pinned to the bottom-right of the image,
            // entirely lowercase, 80% opacity. Small enough to not
            // distract from the puzzle but clearly identifying the
            // source when shared.
            Text("kromatika")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.80))
                .padding(.trailing, 14)
                .padding(.bottom, 10)
        }
        .frame(width: totalW, height: totalH)
    }

    @ViewBuilder
    private func cellSquare(at r: Int, _ c: Int) -> some View {
        let cell = puzzle.board[r][c]
        if cell.kind == .cell, let color = cell.solution {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(OK.toColor(color))
                .frame(width: Self.cellPx, height: Self.cellPx)
        } else {
            Color.clear
                .frame(width: Self.cellPx, height: Self.cellPx)
        }
    }

    private func usedBounds(_ p: Puzzle) -> (minR: Int, maxR: Int, minC: Int, maxC: Int) {
        var minR = Int.max, maxR = Int.min, minC = Int.max, maxC = Int.min
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                if r < minR { minR = r }
                if r > maxR { maxR = r }
                if c < minC { minC = c }
                if c > maxC { maxC = c }
            }
        }
        if minR > maxR { return (0, 0, 0, 0) }
        return (minR, maxR, minC, maxC)
    }
}

/// Presents the system share sheet with a rendered solved-puzzle image.
/// Called from ContentView's solved overlay. Locates the key window so
/// the share sheet has a valid presenter across scenes.
@MainActor
func presentSolvedShare(puzzle: Puzzle) {
    guard let image = SolvedShareImage.render(puzzle: puzzle) else { return }
    let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.keyWindow?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    if let pop = activity.popoverPresentationController {
        pop.sourceView = top.view
        pop.sourceRect = CGRect(x: top.view.bounds.midX,
                                y: top.view.bounds.midY,
                                width: 0, height: 0)
        pop.permittedArrowDirections = []
    }
    top.present(activity, animated: true)
}
