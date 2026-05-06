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
    /// Drives the red show-incorrect border's blink. Oscillates
    /// between 0 and 1 while a wrong cell exists and show-incorrect
    /// is on; stays mid-opacity under reduce-motion so the border is
    /// still visible without strobing.
    @State private var wrongBorderPhase: CGFloat = 0
    /// Latched at touchdown: true when the finger came down on a
    /// cell frame, false when it came down in the gutter. The main
    /// pan gesture consults this to decide whether it's allowed to
    /// pan (gutter only) or must yield to the CellView's own drag
    /// gesture (cell only).
    @State private var panStartLandedOnCell: Bool = false
    /// Sticky flag flipped on by MagnificationGesture's onChanged and
    /// off by onEnded. The pan gesture short-circuits while it's
    /// true so two-finger pinches don't accidentally feed translation
    /// into the pan offset every frame — that simultaneous scale +
    /// shift was the source of the perceived zoom jitter.
    @State private var isPinching: Bool = false

    var body: some View {
        GeometryReader { geo in
            gridContent(size: geo.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func gridContent(size: CGSize) -> some View {
        if let p = game.puzzle {
            let b = (minR: game.puzzleBoundsMinR, maxR: game.puzzleBoundsMaxR,
                     minC: game.puzzleBoundsMinC, maxC: game.puzzleBoundsMaxC)
            let rows = max(1, b.maxR - b.minR + 1)
            let cols = max(1, b.maxC - b.minC + 1)
            let margin: CGFloat = 2
            let padding: CGFloat = 12
            let availW = max(0, size.width - padding * 2)
            let availH = max(0, size.height - padding * 2)
            let perW = (availW / CGFloat(cols)) - margin * 2
            let perH = (availH / CGFloat(rows)) - margin * 2
            let cellPx = max(10, min(64, min(perW, perH)))

            // Two zoom ceilings, both calibrated against screen width
            // so portrait + iPad-landscape obey the same rule (the
            // wider screen yields a more dramatic close-up at the same
            // N-cell target). Cell pitch = cellPx + 2*margin; axis /
            // pitch gives the current 1.0x visible cell count, so axis
            // / (N * pitch) is the multiplier that brings it down to N.
            //   • doubleTapZoom — the preset reached by tapping twice.
            //     5 cells span the screen width.
            //   • pinchMaxZoom — the absolute pinch ceiling. 3 cells
            //     span the screen width.
            let cellPitch = cellPx + margin * 2
            let pinchMaxZoom: CGFloat = max(1.2, size.width / (3 * cellPitch))
            let doubleTapZoom: CGFloat = max(1.2, min(pinchMaxZoom,
                                                      size.width / (5 * cellPitch)))
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
                // Push the unscaled cell pitch once per layout. The
                // screen-space size is derived (`game.renderedCellSize`)
                // so we don't have to re-push it on every zoom tick.
                game.unscaledCellPitch = cellPitch
            }
            .onChange(of: cellPitch) { _, newPitch in
                game.unscaledCellPitch = newPitch
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
                                game.toggleZoom(max: doubleTapZoom)
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
            // pinchMaxZoom (3 cells span the screen width).
            // MagnificationGesture reports a relative multiplier, so
            // we resolve against the snapshot taken at gesture start.
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        isPinching = true
                        game.setZoom(zoomAtGestureStart * value, max: pinchMaxZoom)
                    }
                    .onEnded { _ in
                        isPinching = false
                        zoomAtGestureStart = game.zoomScale
                        // Re-anchor pan bookkeeping after a pinch so
                        // a finger that was about to drag doesn't
                        // resume from a stale baseline (the pinch
                        // ate any in-flight translation while we
                        // were short-circuiting the pan branch).
                        panStartOffset = game.panOffset
                    }
            )
            // Pan gesture. Single DragGesture, gated on zoom. Touches
            // that land on a cell yield to CellView's own gesture
            // (cellFrames lookup); gutter touches pan the grid. Both
            // panStartOffset and panStartLandedOnCell are captured at
            // gesture start (translation ≈ 0) so a cancelled or
            // out-of-order onEnded can't strand stale state into the
            // next gesture. 10pt threshold keeps small wiggles from
            // becoming pans.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in
                        guard game.zoomed else { return }
                        // Two-finger pinch wins over pan. Without this
                        // gate the drag gesture also fires during a
                        // pinch (simultaneous gesture dispatch), and
                        // its translation feeds into panOffset every
                        // frame — so the grid was both scaling AND
                        // shifting during a pinch, which read as
                        // jitter.
                        if isPinching { return }
                        let moved = hypot(v.translation.width,
                                           v.translation.height)
                        if moved < 1 {
                            panStartOffset = game.panOffset
                            // Only LIVE cells block pan. Dead cells
                            // render as black space so panning starts
                            // there should work — the previous
                            // `cellFrames.contains` check covered
                            // every grid slot indiscriminately, which
                            // meant a zoomed-in puzzle (with the
                            // grid filling the viewport) had almost
                            // no pannable surface.
                            panStartLandedOnCell =
                                game.landedOnCell(v.startLocation)
                            return
                        }
                        if panStartLandedOnCell { return }
                        guard moved >= 10 else { return }
                        game.panOffset = CGSize(
                            width: panStartOffset.width + v.translation.width,
                            height: panStartOffset.height + v.translation.height
                        )
                    }
                    .onEnded { _ in
                        panStartLandedOnCell = false
                    }
            )
            .onChange(of: game.zoomed) { _, isZoomed in
                // Snap pan bookkeeping to the new zoom state. On
                // zoom-out game.panOffset has already been cleared by
                // toggleZoom / setZoom; on zoom-in we mirror whatever
                // pan offset is current.
                panStartOffset = isZoomed ? game.panOffset : .zero
                zoomAtGestureStart = game.zoomScale
            }
            // The grid-wide wrongBorder overlay was replaced by
            // per-cell red outlines in CellView, so there's no
            // animation hook to wire here anymore. Leaving the
            // `wrongBorderPhase` state + shape code is harmless but
            // the repeating animation driver that used to update
            // `wrongBorderPhase` at 55 BPM has been removed — it was
            // burning frames on every view update with no visible
            // effect after the refactor.
        }
    }

    /// Paint the pulsing red show-incorrect border around the used
    /// bounds of the puzzle. Replaces the per-cell opacity blink — one
    /// piece of UI to track instead of N cells flashing under different
    /// staggers, and it points at "something here is wrong" without
    /// obscuring the colors themselves.
    @ViewBuilder
    private func wrongBorder(cellPx: CGFloat, margin: CGFloat, padding: CGFloat) -> some View {
        if showWrongBorder {
            let alpha = 0.35 + 0.55 * Double(wrongBorderPhase)
            let strokeW: CGFloat = max(3, cellPx * 0.12)
            RoundedRectangle(cornerRadius: cellPx * 0.38, style: .continuous)
                .stroke(Color.red.opacity(alpha), lineWidth: strokeW)
                .padding(padding - strokeW / 2)
                .allowsHitTesting(false)
        }
    }

    /// True iff the show-incorrect red border should be drawing.
    private var showWrongBorder: Bool {
        game.showIncorrect && game.hasAnyWrongCell
    }


}
