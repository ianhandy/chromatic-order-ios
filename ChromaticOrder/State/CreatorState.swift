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

    /// Active creator tool. Paint is the default; erase deletes
    /// gradients the finger touches; eyedropper copies a committed
    /// cell's color onto `startColor`.
    enum Tool { case paint, erase, eyedropper }
    var tool: Tool = .paint

    /// Cells visited while dragging in erase mode. Drained to
    /// `gradients.removeAll(...)` on drag end.
    var eraseHits: Set<CellIndex> = []

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
    //   existing gradient (cell occupied by a different color, or
    //   edge-adjacent to a different gradient without sharing an
    //   intersection — the crossword-sparsity rule).
    // dragStartOverride / dragEndOverride: when the drag began OR
    //   currently ends on an already-committed cell, these hold those
    //   cells' colors. Either/both can be set:
    //     - start committed → anchor pos 0 at that color
    //     - end committed   → anchor pos (len-1) at that color
    //     - both committed  → lerp between them (startColor / endColor
    //                         inputs are ignored for this drag)
    //   Makes it trivial to extend a gradient, join two segments, or
    //   build a new strip that terminates on an existing palette.
    var dragStart: CellIndex? = nil
    var dragCurrent: CellIndex? = nil
    var dragAxis: Direction? = nil
    var dragInvalid: Bool = false
    var dragStartOverride: OKLCh? = nil
    var dragEndOverride: OKLCh? = nil

    // ─── Player-chosen revealed-at-start cells ──────────────────────
    // When non-empty, the builder uses THIS set as the locked cells
    // instead of auto-locking intersections. Empty → auto-lock as
    // before (intersections + uniqueness guard), so brand-new puzzles
    // still work without touching this.
    var manualLocks: Set<CellIndex> = []

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
        let colors = interpolatedColors(along: cells)
        return zip(cells, colors).map { ($0, $1) }
    }

    /// Does the preview conflict with committed cells?
    ///   1. Intersection mismatch — painting a different color over
    ///      an already-committed cell.
    ///   2. Crossword-sparsity violation — a new (non-intersection)
    ///      preview cell is edge-adjacent to an existing gradient's
    ///      cell that *isn't* part of this drag. That creates the
    ///      illusion of a single gradient where colors don't actually
    ///      step like one.
    func previewConflicts() -> Bool {
        let committed = committedCells
        let preview = previewCells()
        let previewSet = Set(preview.map { $0.idx })
        for (idx, color) in preview {
            // (1) Intersection mismatch.
            if let existing = committed[idx], !OK.equal(existing, color) {
                return true
            }
            // (2) Sparsity — only check NEW cells (not intersections).
            if committed[idx] != nil { continue }
            let neighbors = [
                CellIndex(r: idx.r - 1, c: idx.c),
                CellIndex(r: idx.r + 1, c: idx.c),
                CellIndex(r: idx.r, c: idx.c - 1),
                CellIndex(r: idx.r, c: idx.c + 1),
            ]
            for n in neighbors {
                if committed[n] != nil && !previewSet.contains(n) {
                    return true
                }
            }
        }
        return false
    }

    // ─── Actions ────────────────────────────────────────────────────

    func beginDrag(at idx: CellIndex) {
        let committed = committedCells
        // Empty cell adjacent to exactly one committed cell → pre-seed
        // the drag as if it started from that neighbor, locking the
        // axis in the neighbor-to-tapped direction. Lets the player
        // tap-to-extend a palette one cell (onEnded commits the 2-cell
        // line) and drag to keep extending. Skipped when the tapped
        // cell has multiple committed neighbors — axis is ambiguous.
        if committed[idx] == nil {
            let candidates: [(axis: Direction, neighbor: CellIndex)] = [
                (.h, CellIndex(r: idx.r, c: idx.c - 1)),
                (.h, CellIndex(r: idx.r, c: idx.c + 1)),
                (.v, CellIndex(r: idx.r - 1, c: idx.c)),
                (.v, CellIndex(r: idx.r + 1, c: idx.c)),
            ].filter { committed[$0.neighbor] != nil }
            if candidates.count == 1 {
                let seed = candidates[0]
                dragStart = seed.neighbor
                dragCurrent = idx
                dragAxis = seed.axis
                dragStartOverride = committed[seed.neighbor]
                dragEndOverride = nil
                dragInvalid = previewConflicts()
                return
            }
        }
        dragStart = idx
        dragCurrent = idx
        dragAxis = nil
        dragInvalid = false
        // If the player grabbed an already-committed cell, anchor the
        // new gradient at that cell's color — lets them extend or
        // branch without re-selecting the start chip.
        dragStartOverride = committed[idx]
    }

    /// Erase the gradient(s) containing any of the tapped cells. Used
    /// by the erase tool — single-tap erase clears the hit gradient;
    /// drag-erase accumulates cells and clears everything touched when
    /// the finger lifts.
    func erase(cells: Set<CellIndex>) {
        guard !cells.isEmpty else { return }
        gradients.removeAll { g in
            g.cells.contains(where: { cells.contains($0) })
        }
        manualLocks.subtract(cells)
    }

    /// Eyedropper — copy a committed cell's color onto `startColor`.
    /// Silent no-op on empty cells so the drag-scrub path doesn't
    /// overwrite with a stale value when the finger leaves the grid.
    func pickColor(at idx: CellIndex) {
        if let c = committedCells[idx] { startColor = c }
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
        // Re-check end override against the snapped cell before we
        // clamp — if the player is landing ON a committed cell, the
        // anchored end color defines the gradient's range and the
        // clamp below should respect that.
        dragEndOverride = committedCells[snapped]
        // Extrapolation clamp — when the preview would extend past the
        // usable L/C band (shift mode or past-anchor extrapolation),
        // truncate dragCurrent to the furthest cell whose interpolated
        // color still lives inside the band. Gives the drag a natural
        // "wall" at the palette's edge instead of letting colors march
        // off into clipped / oversaturated territory.
        dragCurrent = snapped
        if let axis = dragAxis {
            let trial = lineCells(from: start, to: snapped, axis: axis)
            let colors = interpolatedColors(along: trial)
            var lastValid = 0
            for i in 0..<trial.count {
                if OK.inUsableBand(colors[i]) {
                    lastValid = i
                } else {
                    break
                }
            }
            if lastValid < trial.count - 1 {
                dragCurrent = trial[lastValid]
                dragEndOverride = committedCells[trial[lastValid]]
            }
        }
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
        dragStartOverride = nil
        dragEndOverride = nil
    }

    /// Toggle whether a cell is revealed at start. Only meaningful for
    /// committed cells — calling it on an empty cell is a no-op.
    func toggleLock(at idx: CellIndex) {
        guard committedCells[idx] != nil else { return }
        if manualLocks.contains(idx) { manualLocks.remove(idx) }
        else { manualLocks.insert(idx) }
    }

    func undo() {
        if !gradients.isEmpty { gradients.removeLast() }
    }

    func clearAll() {
        gradients.removeAll()
        cancelDrag()
    }

    // ─── Color interpolation ────────────────────────────────────────

    /// Piecewise-anchored interpolation.
    ///
    /// Every committed cell along the drag path is a fixed anchor —
    /// the preview's color at that index MUST equal the committed
    /// color (otherwise the preview would visually disagree with the
    /// canvas, which the conflict check catches).
    ///
    /// The implicit ends are anchored too:
    ///   pos 0         → dragStartOverride ?? startColor
    ///   pos count-1   → dragEndOverride   ?? endColor (when set)
    ///
    /// Between adjacent anchors we lerp in OKLab. BEYOND the last
    /// anchor — which happens when the player drags past a committed
    /// cell without picking an end — the gradient continues in the
    /// direction inferred from the last two anchors. This is the
    /// "drag through and past a cell continues the gradient" behavior:
    /// with no endColor set, the committed segment itself defines the
    /// step direction, and new cells beyond it extrapolate linearly
    /// through OKLab. Falls back to {ΔL, Δc, Δh} shift mode only when
    /// there's a single anchor (nothing to infer a direction from).
    private func interpolatedColors(along cells: [CellIndex]) -> [OKLCh] {
        let count = cells.count
        guard count > 0 else { return [] }
        let committed = committedCells

        // Real anchors: every committed cell along the path, in order.
        var anchors: [(pos: Int, color: OKLCh)] = []
        for (i, idx) in cells.enumerated() {
            if let c = committed[idx] { anchors.append((i, c)) }
        }
        // Add implicit anchors for the drag endpoints if the committed
        // anchors don't already cover those positions.
        let s = dragStartOverride ?? startColor
        let e = dragEndOverride ?? endColor
        if !anchors.contains(where: { $0.pos == 0 }) {
            anchors.insert((0, s), at: 0)
        }
        if let e, !anchors.contains(where: { $0.pos == count - 1 }) {
            anchors.append((count - 1, e))
        }

        // Single anchor → shift mode from that anchor (no direction
        // yet to infer).
        if anchors.count == 1 {
            let base = anchors[0]
            return (0..<count).map { i in
                let t = Double(i - base.pos)
                return OKLCh(
                    L: base.color.L + deltaL * t,
                    c: base.color.c + deltaC * t,
                    h: OK.normH(base.color.h + deltaH * t)
                )
            }
        }

        // Two or more anchors → piecewise lerp between bracketing
        // anchors, extrapolate beyond the last using the direction of
        // its preceding neighbor.
        return (0..<count).map { i in
            if i <= anchors.last!.pos {
                for k in 0..<(anchors.count - 1) {
                    let a = anchors[k], b = anchors[k + 1]
                    if i >= a.pos && i <= b.pos {
                        let t = Double(i - a.pos) / Double(max(1, b.pos - a.pos))
                        return lerpLabT(a: a.color, b: b.color, t: t)
                    }
                }
            }
            // Past the last anchor — extrapolate forward.
            let n = anchors.count
            let a = anchors[n - 2], b = anchors[n - 1]
            let t = Double(i - a.pos) / Double(max(1, b.pos - a.pos))
            return lerpLabT(a: a.color, b: b.color, t: t)
        }
    }

    /// Single-t OKLab lerp between two OKLCh points. t is unclamped so
    /// callers can extrapolate beyond an anchor pair by passing t > 1.
    /// Remapped back to OKLCh via (c = hypot, h = atan2) which handles
    /// hue wrap naturally.
    private func lerpLabT(a: OKLCh, b: OKLCh, t: Double) -> OKLCh {
        let la = OK.toLab(a), lb = OK.toLab(b)
        let L = la.L + (lb.L - la.L) * t
        let A = la.a + (lb.a - la.a) * t
        let B = la.b + (lb.b - la.b) * t
        let c = (A * A + B * B).squareRoot()
        var h = atan2(B, A) * 180 / .pi
        if h < 0 { h += 360 }
        return OKLCh(L: L, c: c, h: h)
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
