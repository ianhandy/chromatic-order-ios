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
    /// cell's color onto `startColor`; select draws a marquee +
    /// drags whole gradients around the canvas.
    enum Tool { case paint, erase, eyedropper, select }
    var tool: Tool = .paint

    /// Human-readable name of the active tool — drives the label
    /// rendered under the tool cluster in the kromatika wordmark
    /// style.
    var toolName: String {
        switch tool {
        case .paint: return "paint"
        case .erase: return "erase"
        case .eyedropper: return "eyedropper"
        case .select: return "select"
        }
    }

    /// Cells visited while dragging in erase mode. Drained to
    /// `gradients.removeAll(...)` on drag end.
    var eraseHits: Set<CellIndex> = []

    // ─── Select tool state ──────────────────────────────────────────
    // The select tool runs in two distinct phases:
    //  (1) Marquee draw — empty-canvas drag draws a dashed rect.
    //      Box endpoints are stored in GLOBAL coords so they line up
    //      with cellFrames during commit.
    //  (2) Translate — drag starting on a selected cell shifts all
    //      moving gradients by an integer (dr, dc) in cell units.
    //      Clamp keeps the shifted bounding box inside the canvas.

    /// Cells that are part of the current selection. Populated by
    /// `commitSelectionBox` — expanded to whole gradients so the
    /// player can't accidentally select half a gradient.
    var selectedCells: Set<CellIndex> = []
    /// Marquee box endpoints, in global coords. Both nil when no box
    /// is being drawn.
    var selectionBoxStart: CGPoint? = nil
    var selectionBoxCurrent: CGPoint? = nil
    /// Cell where a translate-drag began. Nil while no translate is
    /// in flight.
    var selectionMoveStartCell: CellIndex? = nil
    /// Live (rows, cols) translation being previewed during a move
    /// drag. Reset to (0, 0) on commit / cancel.
    var selectionMoveDelta: (dr: Int, dc: Int) = (0, 0)
    /// True while the live translate would collide with a
    /// non-selected gradient or leave the canvas. Drives the
    /// preview rect's color so the player sees a bad drop before
    /// they let go.
    var selectionMoveBlocked: Bool = false

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
    /// Virtual anchor at position -1 in the preview. Set when the
    /// drag began as a tap-extend off an existing gradient's
    /// endpoint — holds the color of the cell one step INTO that
    /// gradient (away from the extension direction). The
    /// interpolator treats it as a real anchor at pos -1 so the
    /// extension extrapolates along the existing gradient's own
    /// cell-to-cell step instead of the shift-mode deltas.
    var dragPrevAnchor: OKLCh? = nil

    // ─── Player-chosen revealed-at-start cells ──────────────────────
    // When non-empty, the builder uses THIS set as the locked cells
    // instead of auto-locking intersections. Empty → auto-lock as
    // before (intersections + uniqueness guard), so brand-new puzzles
    // still work without touching this.
    var manualLocks: Set<CellIndex> = []

    // Frame of each canvas cell in global coords (same pattern as
    // GameState.cellFrames). Populated by the canvas view.
    var cellFrames: [CellIndex: CGRect] = [:]

    /// Is the point inside the axis-aligned union of all cell frames?
    /// Used during drag to tell "finger is in the 2pt gap between
    /// cells" (still on the canvas) apart from "finger has left the
    /// canvas entirely" — only the latter should kill the preview.
    private func isInsideCanvas(_ loc: CGPoint) -> Bool {
        guard !cellFrames.isEmpty else { return false }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for r in cellFrames.values {
            if r.minX < minX { minX = r.minX }
            if r.minY < minY { minY = r.minY }
            if r.maxX > maxX { maxX = r.maxX }
            if r.maxY > maxY { maxY = r.maxY }
        }
        return loc.x >= minX && loc.x <= maxX
            && loc.y >= minY && loc.y <= maxY
    }

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
    /// Only intersection mismatches block the drag — painting a
    /// different color over an already-committed cell.
    /// Cells landing edge-adjacent to a different gradient are
    /// allowed; the build pipeline force-locks those so the
    /// player sees them revealed at start (see `autoLockedCells`).
    func previewConflicts() -> Bool {
        let committed = committedCells
        let preview = previewCells()
        for (idx, color) in preview {
            if let existing = committed[idx], !OK.equal(existing, color) {
                return true
            }
        }
        return false
    }

    /// Cells that will be force-locked at build time regardless of
    /// the player's manual-lock choices. Two sources:
    ///  - Sparsity violators: cells edge-adjacent to a DIFFERENT
    ///    gradient without a shared intersection. Would look like
    ///    one gradient even though they're on different lines, so
    ///    they're pre-revealed to eliminate the ambiguity.
    ///  - Duplicate-color cells: two distinct cells whose solution
    ///    colors are perceptually equal have no way for the player
    ///    to tell which goes where, so both are revealed.
    /// The creator canvas renders these the same as manualLocks so
    /// the builder can see exactly what the player will start with.
    var autoLockedCells: Set<CellIndex> {
        var owners: [CellIndex: Set<Int>] = [:]
        var colorsByCell: [CellIndex: OKLCh] = [:]
        for (gi, g) in gradients.enumerated() {
            for (pos, idx) in g.cells.enumerated() {
                owners[idx, default: []].insert(gi)
                colorsByCell[idx] = g.colors[pos]
            }
        }

        var out: Set<CellIndex> = []

        // (1) Sparsity violators.
        for (idx, ownerSet) in owners {
            let neighbors = [
                CellIndex(r: idx.r - 1, c: idx.c),
                CellIndex(r: idx.r + 1, c: idx.c),
                CellIndex(r: idx.r, c: idx.c - 1),
                CellIndex(r: idx.r, c: idx.c + 1),
            ]
            for n in neighbors {
                if let nOwners = owners[n], nOwners.intersection(ownerSet).isEmpty {
                    out.insert(idx)
                    break
                }
            }
        }

        // (2) Duplicate colors across distinct cells.
        let entries = Array(colorsByCell)
        for i in 0..<entries.count {
            for j in (i + 1)..<entries.count {
                if OK.equal(entries[i].value, entries[j].value) {
                    out.insert(entries[i].key)
                    out.insert(entries[j].key)
                }
            }
        }

        return out
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
                // If the neighbor is the endpoint of an existing
                // colinear gradient on this axis, grab the color of
                // the cell one step INTO that gradient so the
                // extension continues its existing step pattern.
                dragPrevAnchor = gradientPrevAnchor(
                    atEndpoint: seed.neighbor, axis: seed.axis
                )
                dragInvalid = previewConflicts()
                return
            }
        }
        dragStart = idx
        dragCurrent = idx
        dragAxis = nil
        dragInvalid = false
        dragPrevAnchor = nil
        // If the player grabbed an already-committed cell, anchor the
        // new gradient at that cell's color — lets them extend or
        // branch without re-selecting the start chip.
        dragStartOverride = committed[idx]
    }

    /// When the drag seed is an endpoint cell of an existing gradient
    /// on the same axis, returns the color of the cell one step
    /// further INSIDE that gradient (i.e., the neighbor's own
    /// neighbor). Returns nil otherwise — for single-cell gradients,
    /// mid-gradient cells, or cross-axis neighbors.
    private func gradientPrevAnchor(atEndpoint cell: CellIndex, axis: Direction) -> OKLCh? {
        for g in gradients where g.dir == axis && g.cells.count >= 2 {
            guard let i = g.cells.firstIndex(of: cell) else { continue }
            if i == g.cells.count - 1 { return g.colors[i - 1] }
            if i == 0                 { return g.colors[i + 1] }
        }
        return nil
    }

    /// Erase the specified cells from whichever gradients contain
    /// them. Single-cell erase: an end-tap trims that endpoint; a
    /// middle-tap splits the gradient into two shorter gradients (one
    /// on each side of the erased cell). Fragments shorter than two
    /// cells are dropped since a gradient needs at least two cells
    /// to define a step.
    func erase(cells: Set<CellIndex>) {
        guard !cells.isEmpty else { return }
        // Capture pre-erase state for undo so the "Clear" path in the
        // erase tool is reversible — not just gradient-commit. Without
        // this, tapping Erase and clearing a stroke permanently
        // destroyed work with no way back.
        pushUndoSnapshot()
        var updated: [LaidGradient] = []
        for g in gradients {
            updated.append(contentsOf: gradientRemoving(cells, from: g))
        }
        gradients = updated
        manualLocks.subtract(cells)
    }

    /// Split/trim `g` by removing the cells in `toRemove`. Returns
    /// the list of remaining gradient fragments (0, 1, or more).
    private func gradientRemoving(_ toRemove: Set<CellIndex>,
                                   from g: LaidGradient) -> [LaidGradient] {
        // Index positions of cells we'd remove. If none, gradient
        // is untouched; if all, it's gone.
        let removeIdx = Set(g.cells.indices.filter { toRemove.contains(g.cells[$0]) })
        if removeIdx.isEmpty { return [g] }
        if removeIdx.count == g.cells.count { return [] }

        // Walk the gradient collecting contiguous runs of kept cells.
        var runs: [(lo: Int, hi: Int)] = []
        var runStart: Int? = nil
        for i in g.cells.indices {
            if removeIdx.contains(i) {
                if let s = runStart {
                    runs.append((s, i - 1))
                    runStart = nil
                }
            } else if runStart == nil {
                runStart = i
            }
        }
        if let s = runStart { runs.append((s, g.cells.count - 1)) }

        return runs.compactMap { run in
            guard run.hi - run.lo + 1 >= 2 else { return nil }
            return LaidGradient(
                dir: g.dir,
                cells: Array(g.cells[run.lo...run.hi]),
                colors: Array(g.colors[run.lo...run.hi])
            )
        }
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
            // No direct hit. This fires both when the finger is
            // OUTSIDE the canvas AND when it's in the 2pt gap
            // between two adjacent cell frames. Resetting the preview
            // on every gap crossing makes the in-progress gradient
            // flicker black for a frame as the finger slides from one
            // cell to the next, so keep the previous drag state when
            // the miss is just a gap. Only kill the preview when the
            // finger is genuinely off the grid.
            if isInsideCanvas(loc) { return }
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
        dragCurrent = snapped
        // Extrapolation clamp — ONLY fires on cells past the last
        // anchor. Between anchors the lerpLabT path can legitimately
        // dip through low-chroma neutrals (hues 180° apart pass
        // through the grey axis mid-interpolation); clamping those
        // breaks normal drags. Past the last anchor is the only
        // place colors march off into oversaturated / out-of-band
        // territory, which is what this guard is for.
        if let axis = dragAxis {
            let trial = lineCells(from: start, to: snapped, axis: axis)
            let committed = committedCells
            let finalPos = trial.count - 1
            var lastAnchorPos = 0
            for (i, idx) in trial.enumerated() where committed[idx] != nil {
                lastAnchorPos = i
            }
            // state.endColor provides an implicit final anchor when
            // bound (non-shift mode) → no extrapolation, no clamp.
            if endColor != nil { lastAnchorPos = finalPos }
            if lastAnchorPos < finalPos {
                let colors = interpolatedColors(along: trial)
                var cutoff = finalPos
                for i in (lastAnchorPos + 1)...finalPos where !OK.inUsableBand(colors[i]) {
                    cutoff = i - 1
                    break
                }
                if cutoff < finalPos {
                    dragCurrent = trial[max(cutoff, 0)]
                    dragEndOverride = committedCells[trial[max(cutoff, 0)]]
                }
            }
        }
        dragInvalid = previewConflicts()
    }

    /// Commit the current preview as a new gradient. No-op if the
    /// preview is empty, a single cell, or invalid.
    func commitDrag() -> Bool {
        defer {
            dragStart = nil; dragCurrent = nil; dragAxis = nil
            dragInvalid = false; dragPrevAnchor = nil
            dragStartOverride = nil; dragEndOverride = nil
        }
        guard let axis = dragAxis else { return false }
        guard !dragInvalid else { return false }
        let preview = previewCells()
        guard preview.count >= 2 else { return false }
        let g = LaidGradient(
            dir: axis,
            cells: preview.map { $0.idx },
            colors: preview.map { $0.color }
        )
        pushUndoSnapshot()
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
        dragPrevAnchor = nil
    }

    // ─── Select tool ────────────────────────────────────────────────

    /// Wipe everything related to the select tool — both the in-flight
    /// marquee box and any committed selection / move preview.
    func clearSelection() {
        selectedCells.removeAll()
        selectionBoxStart = nil
        selectionBoxCurrent = nil
        selectionMoveStartCell = nil
        selectionMoveDelta = (0, 0)
        selectionMoveBlocked = false
    }

    /// Start drawing a marquee. Drops any prior selection; the
    /// player has to commit a brand-new box to re-select.
    func beginSelectionBox(at point: CGPoint) {
        clearSelection()
        selectionBoxStart = point
        selectionBoxCurrent = point
    }

    func updateSelectionBox(to point: CGPoint) {
        guard selectionBoxStart != nil else { return }
        selectionBoxCurrent = point
    }

    /// Finalize the marquee. Cells whose frames intersect the box are
    /// the seed; we then expand to whole gradients so a partially-
    /// covered gradient gets fully selected (the player can't move
    /// half a gradient without breaking it).
    func commitSelectionBox() {
        defer {
            selectionBoxStart = nil
            selectionBoxCurrent = nil
        }
        guard let start = selectionBoxStart, let cur = selectionBoxCurrent
        else { return }
        let rect = CGRect(
            x: min(start.x, cur.x),
            y: min(start.y, cur.y),
            width: abs(start.x - cur.x),
            height: abs(start.y - cur.y)
        )
        var hits: Set<CellIndex> = []
        for (idx, frame) in cellFrames where rect.intersects(frame) {
            hits.insert(idx)
        }
        var full: Set<CellIndex> = []
        for g in gradients where g.cells.contains(where: { hits.contains($0) }) {
            for c in g.cells { full.insert(c) }
        }
        selectedCells = full
    }

    func beginSelectionMove(at idx: CellIndex) {
        selectionMoveStartCell = idx
        selectionMoveDelta = (0, 0)
        selectionMoveBlocked = false
    }

    /// Update the live (dr, dc) translation. Clamp keeps every
    /// selected cell inside the canvas; collision-with-stationary-
    /// gradient is flagged via `selectionMoveBlocked` so the preview
    /// rect can render in a warning color but the drag still tracks.
    func updateSelectionMove(to idx: CellIndex) {
        guard let start = selectionMoveStartCell,
              !selectedCells.isEmpty else { return }
        let rawDR = idx.r - start.r
        let rawDC = idx.c - start.c

        var minR = Int.max, maxR = Int.min
        var minC = Int.max, maxC = Int.min
        for c in selectedCells {
            if c.r < minR { minR = c.r }
            if c.r > maxR { maxR = c.r }
            if c.c < minC { minC = c.c }
            if c.c > maxC { maxC = c.c }
        }
        let drMin = -minR
        let drMax = (Self.canvasRows - 1) - maxR
        let dcMin = -minC
        let dcMax = (Self.canvasCols - 1) - maxC
        let dr = max(drMin, min(drMax, rawDR))
        let dc = max(dcMin, min(dcMax, rawDC))
        selectionMoveDelta = (dr, dc)
        selectionMoveBlocked = moveCollidesWithStationary(dr: dr, dc: dc)
    }

    /// True when the proposed (dr, dc) would land any moving cell on
    /// top of a non-selected cell, OR break an intersection (a
    /// shared cell that belongs to both a moving and non-moving
    /// gradient — moving it would tear the join apart).
    private func moveCollidesWithStationary(dr: Int, dc: Int) -> Bool {
        let movingIndices = gradients.indices.filter { gi in
            gradients[gi].cells.contains(where: { selectedCells.contains($0) })
        }
        let movingCells: Set<CellIndex> = Set(
            movingIndices.flatMap { gradients[$0].cells }
        )
        var stationaryCells: Set<CellIndex> = []
        for gi in gradients.indices where !movingIndices.contains(gi) {
            for c in gradients[gi].cells { stationaryCells.insert(c) }
        }
        // Tear-the-join check: a moving cell that is ALSO part of a
        // stationary gradient can't be moved without breaking the
        // shared intersection. Treat as a collision so the preview
        // turns red and commit aborts.
        for c in movingCells where stationaryCells.contains(c) { return true }
        // Standard collision: a moved cell lands on a stationary one.
        for c in movingCells {
            let dest = CellIndex(r: c.r + dr, c: c.c + dc)
            if stationaryCells.contains(dest) { return true }
        }
        return false
    }

    /// Apply the live `selectionMoveDelta` to all moving gradients,
    /// updating `manualLocks` and `selectedCells` to follow. No-op
    /// when delta is (0, 0) or when the move would collide.
    func commitSelectionMove() {
        defer {
            selectionMoveStartCell = nil
            selectionMoveDelta = (0, 0)
            selectionMoveBlocked = false
        }
        let (dr, dc) = selectionMoveDelta
        guard dr != 0 || dc != 0 else { return }
        guard !selectionMoveBlocked else { return }

        let movingIndices = Set(gradients.indices.filter { gi in
            gradients[gi].cells.contains(where: { selectedCells.contains($0) })
        })
        let movingCells: Set<CellIndex> = Set(
            movingIndices.flatMap { gradients[$0].cells }
        )

        pushUndoSnapshot()
        for gi in movingIndices {
            let g = gradients[gi]
            gradients[gi] = LaidGradient(
                dir: g.dir,
                cells: g.cells.map { CellIndex(r: $0.r + dr, c: $0.c + dc) },
                colors: g.colors
            )
        }
        manualLocks = Set(manualLocks.map { c in
            movingCells.contains(c)
                ? CellIndex(r: c.r + dr, c: c.c + dc)
                : c
        })
        selectedCells = Set(selectedCells.map {
            CellIndex(r: $0.r + dr, c: $0.c + dc)
        })
    }

    /// Toggle whether a cell is revealed at start. Only meaningful for
    /// committed cells — calling it on an empty cell is a no-op.
    func toggleLock(at idx: CellIndex) {
        guard committedCells[idx] != nil else { return }
        pushUndoSnapshot()
        if manualLocks.contains(idx) { manualLocks.remove(idx) }
        else { manualLocks.insert(idx) }
    }

    /// Tiny snapshot of the reversible creator state. Not every field
    /// on CreatorState is captured — only the mutations a user can
    /// "undo" from the bottom bar. Transient drag state isn't; tool
    /// selection isn't (reversing a tool toggle would confuse more
    /// than it helps).
    private struct UndoSnapshot {
        let gradients: [LaidGradient]
        let manualLocks: Set<CellIndex>
    }
    private var undoStack: [UndoSnapshot] = []
    private static let undoStackLimit = 50

    /// Record the current reversible state before mutating. Called
    /// by commitGradient, erase, toggleLock, and clearAll. The stack
    /// caps at 50 entries so an over-eager user doesn't grow it
    /// unbounded across a long session.
    private func pushUndoSnapshot() {
        undoStack.append(UndoSnapshot(
            gradients: gradients,
            manualLocks: manualLocks
        ))
        if undoStack.count > Self.undoStackLimit {
            undoStack.removeFirst(undoStack.count - Self.undoStackLimit)
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        gradients = snap.gradients
        manualLocks = snap.manualLocks
        cancelDrag()
    }

    func clearAll() {
        // Snapshot before nuking so Undo can restore a full canvas.
        // No-op if already empty — don't pollute the stack with
        // identity operations.
        if !gradients.isEmpty || !manualLocks.isEmpty {
            pushUndoSnapshot()
        }
        gradients.removeAll()
        manualLocks.removeAll()
        cancelDrag()
    }

    // ─── Color interpolation ────────────────────────────────────────

    /// Endpoint-only interpolation.
    ///
    /// A gradient has a single uniform OKLab step from cell to cell —
    /// the per-tile shift must be constant within one gradient so
    /// players can deduce the step from any two adjacent cells. That
    /// rules out piecewise slopes, so we anchor ONLY:
    ///   pos -1 (virtual) → dragPrevAnchor, when tap-extending an
    ///                     existing gradient's endpoint (gives the
    ///                     drag the existing gradient's own step).
    ///   pos 0            → dragStartOverride ?? startColor
    ///   pos count-1      → dragEndOverride   ?? endColor (when set)
    ///
    /// Mid-path committed cells are NOT used as anchors. Instead
    /// they're checked in previewConflicts — if the linearly-
    /// interpolated value at their position doesn't match the
    /// committed color, the drag can't commit. That pushes the
    /// player to pick endpoints that produce a line passing through
    /// whichever intersections they're crossing.
    ///
    /// Shift mode kicks in only when there's a single endpoint
    /// anchor (no end color picked), advancing by (ΔL, Δc, Δh).
    private func interpolatedColors(along cells: [CellIndex]) -> [OKLCh] {
        let count = cells.count
        guard count > 0 else { return [] }

        let s = dragStartOverride ?? startColor
        let e = dragEndOverride ?? endColor

        var anchors: [(pos: Int, color: OKLCh)] = [(0, s)]
        // Virtual -1 anchor from tap-extend: the cell one step INTO
        // the existing gradient, so the linear extrapolation follows
        // its established step.
        if let prev = dragPrevAnchor {
            anchors.insert((-1, prev), at: 0)
        }
        if let e {
            anchors.append((count - 1, e))
        }

        // Single anchor → shift mode.
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

        // Two or three anchors — always linear between the first and
        // last. Skip the OKLab roundtrip when `i` lands exactly on an
        // anchor (atan2 recovery is unstable for near-gray colors).
        let first = anchors.first!
        let last = anchors.last!
        let span = Double(max(1, last.pos - first.pos))
        return (0..<count).map { i in
            if let hit = anchors.first(where: { $0.pos == i }) {
                return hit.color
            }
            let t = Double(i - first.pos) / span
            return lerpLabT(a: first.color, b: last.color, t: t)
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
