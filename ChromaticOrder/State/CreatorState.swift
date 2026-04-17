//  Observable model for the puzzle creator. Owns the canvas, the
//  color inputs, the list of laid gradients, and the in-progress
//  drag preview. Validation / difficulty / serialization lives in
//  CreatorValidator.swift; this file is just the state container.

import Foundation
import SwiftUI

@MainActor
@Observable
final class CreatorState {
    // Canvas dimensions — picked to be comfortable on phone:
    // 11 cols × 9 rows keeps every cell thumb-reachable and leaves
    // room above/below for the toolbar + swatches.
    static let canvasCols: Int = 11
    static let canvasRows: Int = 9

    // Laid gradients. Order matters for undo (last laid = undone first).
    var gradients: [LaidGradient] = []

    // Color inputs.
    //   startColor: always set.
    //   endColor: nil → "shift mode" (use delta* below to roll colors).
    var startColor: OKLCh = OKLCh(L: 0.60, c: 0.15, h: 40)
    var endColor: OKLCh? = OKLCh(L: 0.45, c: 0.15, h: 220)

    // Shift-mode step (per cell). Only consulted when endColor == nil.
    // Reasonable defaults mirror Trivial-level ranges.
    var deltaL: Double = 0
    var deltaC: Double = 0
    var deltaH: Double = 25

    // ─── Drag preview state ─────────────────────────────────────────
    // dragStart: the cell where the drag began (first contact).
    // dragCurrent: the cell currently under the finger, AFTER snapping
    //   to the dominant axis so the preview is one-dimensional.
    // dragAxis: h or v — locked on the second cell to avoid diagonal
    //   gradients. If nil, the player hasn't moved far enough yet.
    // dragInvalid: true when the current line would conflict with an
    //   existing gradient (cell occupied by a different color).
    var dragStart: CellIndex? = nil
    var dragCurrent: CellIndex? = nil
    var dragAxis: Direction? = nil
    var dragInvalid: Bool = false

    // Frame of each canvas cell in global coords (same pattern as
    // GameState.cellFrames). Populated by the canvas view.
    var cellFrames: [CellIndex: CGRect] = [:]

    // ─── Derived ────────────────────────────────────────────────────

    /// The committed colors for each cell — flattened from all laid
    /// gradients. Used for rendering the static canvas and for
    /// intersection-conflict checks during a drag.
    var committedCells: [CellIndex: OKLCh] {
        var out: [CellIndex: OKLCh] = [:]
        for g in gradients {
            for (i, idx) in g.cells.enumerated() {
                out[idx] = g.colors[i]
            }
        }
        return out
    }

    /// Preview cells for the current drag — the line from dragStart to
    /// dragCurrent (snapped to dragAxis) with interpolated colors.
    /// Empty when no drag is in flight.
    func previewCells() -> [(idx: CellIndex, color: OKLCh)] {
        guard let start = dragStart, let end = dragCurrent, let axis = dragAxis
        else { return [] }
        let cells = lineCells(from: start, to: end, axis: axis)
        let colors = interpolatedColors(count: cells.count)
        return zip(cells, colors).map { ($0, $1) }
    }

    /// Does the preview conflict with committed cells? Conflict = the
    /// preview paints a different-enough color (ΔE > 2) over an already-
    /// committed cell.
    func previewConflicts() -> Bool {
        let committed = committedCells
        for (idx, color) in previewCells() {
            if let existing = committed[idx], !OK.equal(existing, color) {
                return true
            }
        }
        return false
    }

    // ─── Actions ────────────────────────────────────────────────────

    func beginDrag(at idx: CellIndex) {
        dragStart = idx
        dragCurrent = idx
        dragAxis = nil
        dragInvalid = false
    }

    func updateDrag(to loc: CGPoint) {
        guard let start = dragStart else { return }
        // Which cell is under the finger? Direct-hit only — no
        // magnetism here; the creator needs a precise feel.
        let hit = cellFrames.first(where: { $0.value.contains(loc) })?.key
        guard let cur = hit else {
            // Off-grid → kill the preview (no partial commits).
            dragCurrent = start
            dragAxis = nil
            dragInvalid = false
            return
        }
        // Lock axis on first non-start cell. If the player moves back
        // to start the axis stays — once committed it's sticky through
        // the drag.
        if dragAxis == nil, cur != start {
            let dr = abs(cur.r - start.r)
            let dc = abs(cur.c - start.c)
            dragAxis = dr >= dc ? .v : .h
        }
        // Snap the current cell onto the locked axis so the preview
        // stays a straight horizontal or vertical line.
        let snapped: CellIndex = {
            guard let axis = dragAxis else { return cur }
            return axis == .h
                ? CellIndex(r: start.r, c: cur.c)
                : CellIndex(r: cur.r,   c: start.c)
        }()
        dragCurrent = snapped
        dragInvalid = previewConflicts()
    }

    /// Commit the current preview as a new gradient. No-op if the
    /// preview is empty, a single cell, or invalid.
    func commitDrag() -> Bool {
        defer { dragStart = nil; dragCurrent = nil; dragAxis = nil; dragInvalid = false }
        guard let axis = dragAxis else { return false }
        guard !dragInvalid else { return false }
        let preview = previewCells()
        guard preview.count >= 2 else { return false }
        let g = LaidGradient(
            dir: axis,
            cells: preview.map { $0.idx },
            colors: preview.map { $0.color }
        )
        gradients.append(g)
        return true
    }

    func cancelDrag() {
        dragStart = nil
        dragCurrent = nil
        dragAxis = nil
        dragInvalid = false
    }

    func undo() {
        if !gradients.isEmpty { gradients.removeLast() }
    }

    func clearAll() {
        gradients.removeAll()
        cancelDrag()
    }

    // ─── Color interpolation ────────────────────────────────────────

    /// Interpolate (or shift-step) `count` colors along this gradient.
    /// If endColor is set, lerps startColor → endColor in OKLab space
    /// and maps back to OKLCh so the perceptual steps are even. If
    /// endColor is nil, applies the shift delta per cell.
    private func interpolatedColors(count: Int) -> [OKLCh] {
        guard count > 0 else { return [] }
        if let end = endColor, count >= 2 {
            return lerpLab(from: startColor, to: end, count: count)
        }
        return (0..<count).map { i in
            let t = Double(i)
            return OKLCh(
                L: startColor.L + deltaL * t,
                c: startColor.c + deltaC * t,
                h: OK.normH(startColor.h + deltaH * t)
            )
        }
    }

    /// Straight line in OKLab from a to b, remapped to OKLCh. Matches
    /// how the web version's gradient builder steps through color
    /// space — perceptually uniform, handles hue-wrap naturally.
    private func lerpLab(from a: OKLCh, to b: OKLCh, count: Int) -> [OKLCh] {
        let la = OK.toLab(a), lb = OK.toLab(b)
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            let L = la.L + (lb.L - la.L) * t
            let A = la.a + (lb.a - la.a) * t
            let B = la.b + (lb.b - la.b) * t
            // Back from (L, a, b) to OKLCh: c = hypot(a, b); h = atan2.
            let c = (A * A + B * B).squareRoot()
            var h = atan2(B, A) * 180 / .pi
            if h < 0 { h += 360 }
            return OKLCh(L: L, c: c, h: h)
        }
    }

    /// Cells along the line from `start` to `end`, orthogonal only.
    /// Inclusive on both endpoints. `axis` chooses which coordinate
    /// to advance.
    private func lineCells(from start: CellIndex, to end: CellIndex, axis: Direction) -> [CellIndex] {
        switch axis {
        case .h:
            let lo = min(start.c, end.c), hi = max(start.c, end.c)
            let r = start.r
            // Direction of travel — if drag went right-to-left, color
            // A is still the first cell the player touched (start).
            return start.c <= end.c
                ? (lo...hi).map { CellIndex(r: r, c: $0) }
                : (lo...hi).reversed().map { CellIndex(r: r, c: $0) }
        case .v:
            let lo = min(start.r, end.r), hi = max(start.r, end.r)
            let c = start.c
            return start.r <= end.r
                ? (lo...hi).map { CellIndex(r: $0, c: c) }
                : (lo...hi).reversed().map { CellIndex(r: $0, c: c) }
        }
    }
}

/// One committed gradient from the creator. Cells are in player-order
/// (i.e., the first cell is where they started dragging, matches the
/// startColor). dir is the axis they dragged along.
struct LaidGradient: Identifiable, Equatable, Hashable {
    let id = UUID()
    var dir: Direction
    var cells: [CellIndex]
    var colors: [OKLCh]
}
