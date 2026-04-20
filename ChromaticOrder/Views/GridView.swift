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
    /// Snapshot of game.zoomScale at pinch gesture start — used to
    /// resolve MagnificationGesture's relative magnitude into an
    /// absolute new zoom value.
    @State private var zoomAtGestureStart: CGFloat = 1.0
    /// Manual double-tap tracking — SwiftUI's onTapGesture(count:) has
    /// no distance threshold, so two taps on different cells could
    /// register as a double-tap. We enforce both a time window and a
    /// distance window so only genuine double-taps on the same spot
    /// toggle the zoom.
    @State private var lastTapAt: Date = .distantPast
    @State private var lastTapLoc: CGPoint = .zero

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

            // Max zoom — stop at "roughly 8 cells span the short viewport
            // axis." That keeps enough of the puzzle in frame to plan
            // moves while still magnifying cells past their 1.0x size.
            // Cell pitch = cellPx + 2*margin; short-axis / pitch gives
            // how many cells are currently visible at 1.0x, so
            // (current / 8) is the multiplier that drops the visible
            // count to 8.
            let cellPitch = cellPx + margin * 2
            let shortAxis = min(size.width, size.height)
            let maxZoom: CGFloat = max(1.2, shortAxis / (8 * cellPitch))
            let zoom: CGFloat = game.zoomScale

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
            .onAppear {
                // Report the on-screen cell size (post-zoom) to
                // GameState so the drag-ghost lift scales with it.
                game.renderedCellSize = cellPitch * zoom
            }
            .onChange(of: zoom) { _, newZoom in
                game.renderedCellSize = cellPitch * newZoom
            }
            .onChange(of: cellPitch) { _, newPitch in
                game.renderedCellSize = newPitch * zoom
            }
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.95),
                       value: game.panOffset)
            .onPreferenceChange(CellFramesKey.self) { frames in
                // Cell frames are reported in GLOBAL coords and already
                // reflect scaleEffect + offset, so the hit-test maps
                // touches correctly in zoomed + unzoomed states.
                Task { @MainActor in game.cellFrames = frames }
            }
            .simultaneousGesture(
                SpatialTapGesture(count: 1, coordinateSpace: .local)
                    .onEnded { event in
                        let now = Date()
                        let dt = now.timeIntervalSince(lastTapAt)
                        let dist = hypot(
                            event.location.x - lastTapLoc.x,
                            event.location.y - lastTapLoc.y
                        )
                        // Both time and distance must match. The time
                        // window is player-configurable (Accessibility
                        // sheet) so slow-fingered players can loosen
                        // it without needing code changes. Distance
                        // stays tight (24pt) regardless — that's about
                        // filtering spurious re-taps, not ergonomics.
                        if dt < game.doubleTapInterval, dist < 24 {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                game.toggleZoom(max: maxZoom)
                            }
                            zoomAtGestureStart = game.zoomScale
                            lastTapAt = .distantPast
                            lastTapLoc = .zero
                        } else {
                            lastTapAt = now
                            lastTapLoc = event.location
                        }
                    }
            )
            // Pinch to zoom — clamped between 1x (default view) and
            // maxZoom (3 cells span the short axis). MagnificationGesture
            // reports a relative multiplier, so we resolve against the
            // snapshot taken at gesture start.
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        game.setZoom(zoomAtGestureStart * value, max: maxZoom)
                    }
                    .onEnded { _ in
                        zoomAtGestureStart = game.zoomScale
                    }
            )
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
                zoomAtGestureStart = game.zoomScale
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
