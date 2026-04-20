//  Rasterizes a solved puzzle to a shareable PNG. The view renders a
//  clean static grid with just the solution colors — no drag handles,
//  no bank, no overlays — plus a small "kromatika" wordmark so the
//  image is recognizable once it leaves the app.

import SwiftUI
import UIKit

@MainActor
enum SolvedShareImage {
    /// Render the puzzle's solution grid to a UIImage. Returns nil on
    /// the rare occasion ImageRenderer fails to produce a CGImage.
    static func render(puzzle: Puzzle, level: Int) -> UIImage? {
        let renderer = ImageRenderer(content: SolvedGridSnapshot(puzzle: puzzle, level: level))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

private struct SolvedGridSnapshot: View {
    let puzzle: Puzzle
    let level: Int

    private static let cellPx: CGFloat = 56
    private static let spacing: CGFloat = 3
    private static let padding: CGFloat = 32

    var body: some View {
        let b = usedBounds(puzzle)
        let rows = max(1, b.maxR - b.minR + 1)
        let cols = max(1, b.maxC - b.minC + 1)
        VStack(spacing: 14) {
            VStack(spacing: Self.spacing) {
                ForEach(b.minR...b.maxR, id: \.self) { r in
                    HStack(spacing: Self.spacing) {
                        ForEach(b.minC...b.maxC, id: \.self) { c in
                            cellSquare(at: r, c)
                        }
                    }
                }
            }
            Text("kromatika · lv \(level)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(Self.padding)
        .frame(
            width: CGFloat(cols) * Self.cellPx
                + CGFloat(max(0, cols - 1)) * Self.spacing
                + Self.padding * 2,
            height: CGFloat(rows) * Self.cellPx
                + CGFloat(max(0, rows - 1)) * Self.spacing
                + Self.padding * 2 + 28
        )
        .background(Color.black)
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
func presentSolvedShare(puzzle: Puzzle, level: Int) {
    guard let image = SolvedShareImage.render(puzzle: puzzle, level: level) else { return }
    let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
    guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.keyWindow?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    // iPad requires a popover source; anchor to top's view center.
    if let pop = activity.popoverPresentationController {
        pop.sourceView = top.view
        pop.sourceRect = CGRect(x: top.view.bounds.midX,
                                y: top.view.bounds.midY,
                                width: 0, height: 0)
        pop.permittedArrowDirections = []
    }
    top.present(activity, animated: true)
}
