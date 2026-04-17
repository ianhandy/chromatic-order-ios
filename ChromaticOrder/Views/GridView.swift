//  The puzzle grid. Each cell is a CellView with drag/tap handling.
//  cellPx is computed from the available frame so the whole grid
//  always fits — never scrolls.
//
//  Zoom: double-tapping the grid toggles a scale-up to fill as much
//  of the viewport as possible. While zoomed, a single-finger drag on
//  the grid pans (cell-level drags are disabled for that mode — the
//  player zooms out to rearrange). Taps still place swatches in both
//  states. Double-tap again zooms out and clears the pan offset.

import SwiftUI

struct GridView: View {
    @Bindable var game: GameState
    @State private var panStartOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            gridContent(size: geo.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func gridContent(size: CGSize) -> some View {
        if let p = game.puzzle {
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

            // Zoom scale — pick whatever makes the grid fit the limiting
            // axis of the container exactly. Caps at 2.5× so tiny puzzles
            // (single-gradient Trivial) don't bloat past usefulness.
            let gridTotalW = CGFloat(cols) * (cellPx + margin * 2)
            let gridTotalH = CGFloat(rows) * (cellPx + margin * 2)
            let fillScale = min(
                size.width  / max(gridTotalW, 1),
                size.height / max(gridTotalH, 1)
            )
            let zoom: CGFloat = game.zoomed ? min(2.5, max(1.5, fillScale)) : 1.0

            VStack(spacing: 0) {
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
            .scaleEffect(zoom, anchor: .center)
            .offset(game.panOffset)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: game.zoomed)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.95),
                       value: game.panOffset)
            .onPreferenceChange(CellFramesKey.self) { frames in
                // Cell frames are reported in GLOBAL coords and already
                // reflect scaleEffect + offset, so the hit-test maps
                // touches correctly in zoomed + unzoomed states.
                Task { @MainActor in game.cellFrames = frames }
            }
            .onTapGesture(count: 2) {
                game.toggleZoom()
            }
            // Pan gesture — only wired up while zoomed. CellView's own
            // drag gesture is suppressed by `game.zoomed` (see CellView)
            // so they don't fight. Translation is added to the offset
            // captured at gesture start so pan accumulates naturally.
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        guard game.zoomed else { return }
                        game.panOffset = CGSize(
                            width:  panStartOffset.width  + v.translation.width,
                            height: panStartOffset.height + v.translation.height
                        )
                    }
                    .onEnded { _ in
                        guard game.zoomed else { return }
                        panStartOffset = game.panOffset
                    }
            )
            .onChange(of: game.zoomed) { _, isZoomed in
                // Reset pan bookkeeping whenever zoom toggles so the
                // next pan starts from the new (possibly-zero) offset.
                panStartOffset = isZoomed ? game.panOffset : .zero
            }
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
