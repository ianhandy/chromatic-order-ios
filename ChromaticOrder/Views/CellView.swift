//  Individual cell. Glow layer behind (when solved), color layer in
//  front. Drag detection via SwiftUI DragGesture with coordinate space
//  reported up to GameState.

import SwiftUI

struct CellFramesKey: PreferenceKey {
    static var defaultValue: [CellIndex: CGRect] = [:]
    static func reduce(value: inout [CellIndex: CGRect], nextValue: () -> [CellIndex: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CellView: View {
    let r: Int
    let c: Int
    let cell: BoardCell
    let cellPx: CGFloat
    @Bindable var game: GameState
    @State private var shakePhase: CGFloat = 0

    var body: some View {
        let filled = cell.kind == .cell && cell.placed != nil
        let placed = cell.placed
        let radius = cellPx * 0.26

        ZStack {
            if cell.kind == .dead {
                Color.clear
            } else {
                // Empty-cell tint — light-on-dark now that the backdrop
                // is black. Bumped from 0.08 → 0.14 alpha so the empty
                // slots are clearly visible as drop targets without
                // pulling focus from filled cells.
                if !filled {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(width: cellPx, height: cellPx)
                }
                // Solved-burst glow behind color (z-order wise).
                // Gated on reduce-motion AND the explicit glow toggle
                // so players can keep motion on but skip this
                // specific effect. A "perfect" solve (no mistakes,
                // no peeks, each placement right on the first try)
                // scales the bleed with puzzle difficulty so tougher
                // puzzles reward the clean solve more visibly.
                if filled, let color = placed, game.solved,
                   !game.reduceMotion, game.solvedGlowEnabled {
                    let diff = Double(game.puzzle?.difficulty ?? 1)
                    // Perfect solves scale the bleed hard — at max
                    // difficulty a perfect solve is ~2x the bleed of
                    // a normal solve. Normal solves also get a
                    // baseline boost so every solve feels more
                    // explosive than before.
                    let perfectBoost = game.isPerfectSolve
                        ? 2.5 + 2.5 * (diff / 10.0)
                        : 1.1
                    SolvedBurstGlow(
                        color: color,
                        cellPx: cellPx,
                        phase: Double(r) * 0.17 + Double(c) * 0.31,
                        perfectBoost: perfectBoost
                    )
                    .frame(width: cellPx, height: cellPx)
                }
                // Color layer (front)
                if filled, let color = placed {
                    ColorFace(color: color,
                              selected: isSelected,
                              wrong: isWrong,
                              cellPx: cellPx,
                              radius: radius,
                              reduceMotion: game.reduceMotion,
                              shakePhase: shakePhase)
                }

                // Perfect-solve shine — a specular highlight whose
                // position tracks the current tilt of the solved
                // board. Permanent (not animated in waves); moves
                // across each cell as the player rotates the puzzle
                // with the post-solve tilt gesture, reading like
                // light glinting off a card. Intensity scales with
                // puzzle difficulty.
                if filled, placed != nil, game.solved, game.isPerfectSolve,
                   !game.reduceMotion, game.solvedGlowEnabled {
                    let diff = Double(game.puzzle?.difficulty ?? 1)
                    let intensity = min(1.0, 0.35 + 0.65 * diff / 10.0)
                    PerfectSolveShine(
                        cellPx: cellPx,
                        radius: radius,
                        intensity: intensity
                    )
                    .allowsHitTesting(false)
                }

                // Drop-target TINT. When the player is dragging a swatch
                // and magnetism has snapped to this cell, fill the cell
                // with the held color at a moderate opacity — near-instant
                // fade-in so the player can SEE the placement land here
                // before they release. No outline; the tint itself is the
                // cue. Removed on the next frame when magnetism moves on.
                if isDropTarget, !cell.locked, let held = game.heldColor {
                    // Gradual fade-in so the tint swells into view as
                    // the ghost snaps — 220ms feels like the cell is
                    // *becoming* the placed color, not flashing.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(OK.toColor(held, opacity: 0.9))
                        .frame(width: cellPx, height: cellPx)
                        .transition(.opacity.animation(.easeInOut(duration: 0.22)))
                }

                // Locked-cell marker — small filled dot at the cell's
                // center, painted in the cell's complementary color
                // (opposite hue + inverted lightness via OK.opposite).
                // High contrast against the cell's own color, reads as
                // "this cell is fixed." Hidden once the puzzle is
                // solved so the completed grid is just color.
                if cell.locked, filled, !game.solved, let color = placed {
                    Circle()
                        .fill(OK.toColor(OK.opposite(color), opacity: 0.9))
                        .frame(width: cellPx * 0.22, height: cellPx * 0.22)
                }

            }
        }
        .opacity(isDragSource ? 0.3 : 1.0)
        .frame(width: cellPx, height: cellPx)
        .background(
            GeometryReader { geo in
                // Report global frame so GameState can hit-test drags
                // started from any view (swatch or another cell) against
                // this cell without needing per-cell drop handlers.
                Color.clear.preference(
                    key: CellFramesKey.self,
                    value: [CellIndex(r: r, c: c): geo.frame(in: .global)]
                )
            }
        )
        .contentShape(Rectangle())
        // One unified gesture so tap and drag can't both fire off the
        // same release (the previous `onTapGesture + simultaneous
        // DragGesture` pair let a brief drag re-register as a tap on
        // liftoff, placing an unintended color). Translation magnitude
        // disambiguates tap from drag on end.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    // Below 5pt we're still in tap territory — don't
                    // start a drag yet.
                    guard moved >= 5 else { return }
                    // No drags on locked cells, and nothing once the
                    // puzzle is solved — the board is frozen after
                    // completion. Cell drags now work in both zoomed
                    // and unzoomed states; the grid-level pan gesture
                    // consults `game.cellFrames` at startLocation and
                    // skips itself when the finger lands on a cell, so
                    // the two gestures no longer fight.
                    if filled, !cell.locked, !game.solved,
                       game.dragSource == nil, let placedColor = placed {
                        game.beginDrag(
                            DragSource(kind: .cell(CellIndex(r: r, c: c)), color: placedColor),
                            at: v.location
                        )
                    }
                    if game.dragSource != nil {
                        game.updateDrag(to: v.location)
                    }
                }
                .onEnded { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    if case .cell(let idx) = game.dragSource?.kind,
                       idx == CellIndex(r: r, c: c) {
                        game.endDrag(moved: true)
                    } else if moved < 5, game.dragSource == nil {
                        // Real tap — no drag ever started from here
                        // and the finger never left the cell.
                        game.tapCell(at: r, c)
                    }
                }
        )
    }

    // ─── derived flags ──────────────────────────────────────────────

    private var isSelected: Bool {
        if case .cell(let idx) = game.selection?.kind {
            return idx == CellIndex(r: r, c: c)
        }
        return false
    }

    private var isDropTarget: Bool {
        if case .cell(let idx) = game.dropTarget { return idx == CellIndex(r: r, c: c) }
        return false
    }

    private var isDragSource: Bool {
        if case .cell(let idx) = game.dragSource?.kind {
            return idx == CellIndex(r: r, c: c)
        }
        return false
    }

    private var isWrong: Bool {
        guard cell.kind == .cell, !cell.locked,
              let placed = cell.placed, let sol = cell.solution else { return false }
        return game.showIncorrect && !OK.equal(placed, sol)
    }
}

// ─── pieces ──────────────────────────────────────────────────────────

private struct ColorFace: View {
    let color: OKLCh
    let selected: Bool
    let wrong: Bool
    let cellPx: CGFloat
    let radius: CGFloat
    let reduceMotion: Bool
    let shakePhase: CGFloat

    var body: some View {
        // Wrong-cell rotation removed per player feedback — the
        // gyration read as distracting. Per-cell red outline replaces
        // the old grid-wide border so the player can see exactly which
        // placements are wrong. `shakePhase` stays wired up only for
        // future tweaks; the rotation itself is now always zero.
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(color))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: 0.5)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .overlay(
                // Wrong-cell red outline. Only renders when the parent
                // flipped `wrong = true`; a solid stroke rather than
                // the old blink so the marker stays legible while the
                // player is still placing swatches.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: max(1.5, cellPx * 0.06))
                    .stroke(Color.red.opacity(wrong ? 0.95 : 0),
                            lineWidth: max(2.5, cellPx * 0.09))
                    .animation(.easeInOut(duration: 0.18), value: wrong)
            )
            .shadow(color: selected ? .black.opacity(0.18) : .clear,
                    radius: selected ? 9 : 0, y: selected ? 4 : 0)
            .frame(width: cellPx, height: cellPx)
            .scaleEffect(selected ? 1.08 : 1)
            .offset(y: selected ? -4 : 0)
            .animation(.easeOut(duration: 0.38), value: selected)
    }
}

private struct SolvedBurstGlow: View {
    let color: OKLCh
    let cellPx: CGFloat
    let phase: Double          // 0..1 per-cell stagger input
    /// 0 on an ordinary solve; up to 1.0 on a perfect solve with
    /// difficulty 10. Scales the bleed's blur + cell-scale headroom
    /// so perfect clears on higher tiers bloom visibly more.
    var perfectBoost: Double = 0
    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        let stagger = phase * 0.6
        let lowAlpha: Double = 0.65
        let highAlpha: Double = 1.00
        // Static blur — animating blur radius on 100+ cells
        // simultaneously is the heaviest per-frame GPU operation.
        // A single fixed radius still reads as a soft halo; only
        // opacity + scale animate.
        let blurR: CGFloat = cellPx * (3.5 + CGFloat(2.5 * perfectBoost))
        let lowScale: CGFloat = 1.25 + CGFloat(0.35 * perfectBoost)
        let highScale: CGFloat = 2.20 + CGFloat(0.75 * perfectBoost)
        let alpha = appeared ? (pulse ? highAlpha : lowAlpha) : 0
        let scale: CGFloat = appeared ? (pulse ? highScale : lowScale) : 0.9
        RoundedRectangle(cornerRadius: cellPx * 0.26, style: .continuous)
            .fill(OK.toColor(color, opacity: alpha))
            .frame(width: cellPx, height: cellPx)
            .blur(radius: blurR)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    appeared = true
                }
                withAnimation(
                    .easeInOut(duration: 2.2)
                        .repeatForever(autoreverses: true)
                        .delay(stagger)
                ) {
                    pulse = true
                }
            }
    }
}

/// Perfect-solve specular highlight. Static — does not move with
/// tilt, does not animate. A faint diagonal sheen baked into each
/// cell so the player can see the board is "different" after a
/// perfect solve without the shine competing with the color bleed.
private struct PerfectSolveShine: View {
    let cellPx: CGFloat
    let radius: CGFloat
    let intensity: Double

    var body: some View {
        let bandWidth = cellPx * 0.9
        // Dramatically quieter than the previous pass — peak alpha
        // caps around 0.14 so the sheen is subtle ambient detail
        // rather than a bright streak.
        let peak = 0.05 + 0.09 * intensity
        let gradient = LinearGradient(
            stops: [
                .init(color: .white.opacity(0),            location: 0.00),
                .init(color: .white.opacity(peak * 0.35), location: 0.40),
                .init(color: .white.opacity(peak),         location: 0.50),
                .init(color: .white.opacity(peak * 0.35), location: 0.60),
                .init(color: .white.opacity(0),            location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        Rectangle()
            .fill(gradient)
            .frame(width: bandWidth, height: cellPx * 1.6)
            .rotationEffect(.degrees(22))
            .frame(width: cellPx, height: cellPx)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
