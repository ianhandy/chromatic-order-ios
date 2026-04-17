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
                // is black. Translucent white keeps the empty slots
                // visible without pulling focus from filled cells.
                if !filled {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: cellPx, height: cellPx)
                }
                // Solved-burst glow behind color (z-order wise)
                if filled, let color = placed, game.solved, !game.reduceMotion {
                    SolvedBurstGlow(color: color, cellPx: cellPx, phase: Double(r) * 0.17 + Double(c) * 0.31)
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

                // Locked-cell marker — interior border stroked in the
                // cell's complementary color (opposite hue + inverted
                // lightness, via OK.opposite). High-contrast, reads as
                // "this cell is fixed." Disappears once the puzzle is
                // solved so the completed grid shows nothing but color.
                if cell.locked, filled, !game.solved, let color = placed {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            OK.toColor(OK.opposite(color), opacity: 0.85),
                            lineWidth: max(2, cellPx * 0.08)
                        )
                        .frame(width: cellPx, height: cellPx)
                }

                // Red-outline wrong indicator
                if isWrong {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color(red: 0.8, green: 0.2, blue: 0.2), lineWidth: 3)
                        .frame(width: cellPx, height: cellPx)
                }
            }
        }
        .opacity(isDragSource ? 0.3 : 1)
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
        .onTapGesture {
            game.tapCell(at: r, c)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { v in
                    // No drags on locked cells, and nothing once the
                    // puzzle is solved — the board is frozen after
                    // completion so the finished gradient can breathe.
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
                .onEnded { _ in
                    if case .cell(let idx) = game.dragSource?.kind, idx == CellIndex(r: r, c: c) {
                        game.endDrag(moved: true)
                    }
                }
        )
        .onChange(of: isWrong) { _, newValue in
            if newValue && !game.reduceMotion {
                // Kick off the wrong-shake loop; SwiftUI animation handles
                // the oscillation via the phase variable.
                withAnimation(.easeInOut(duration: 0.7)
                              .repeatForever(autoreverses: true)
                              .delay(Double((r * 13 + c * 29) % 200) / 1000)) {
                    shakePhase = 1
                }
            } else {
                shakePhase = 0
            }
        }
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
        let offset: CGFloat = reduceMotion ? 0 : (wrong ? (shakePhase - 0.5) * 2.5 : 0)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(color))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: 0.5)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: selected ? .black.opacity(0.18) : .clear,
                    radius: selected ? 9 : 0, y: selected ? 4 : 0)
            .frame(width: cellPx, height: cellPx)
            .scaleEffect(selected ? 1.08 : 1)
            .offset(x: offset, y: selected ? -4 : 0)
            .animation(.easeOut(duration: 0.38), value: selected)
    }
}

private struct SolvedBurstGlow: View {
    let color: OKLCh
    let cellPx: CGFloat
    let phase: Double          // 0..1 per-cell stagger input
    @State private var burst = false  // sharp initial flash
    @State private var settled = false // gentle easing back

    var body: some View {
        // Color + blur instead of .shadow — SwiftUI's shadow requires
        // opaque pixels to cast from, and a Color.clear fill casts no
        // shadow. A filled translucent RRect with .blur produces the
        // halo directly, plays well with scaleEffect, and actually
        // animates (animatable modifiers compose, opaque-shape shadow
        // does not animate radius reliably).
        let stagger = phase * 0.08
        let peakAlpha: Double = 0.85
        let restAlpha: Double = 0.55
        let alpha = burst ? (settled ? restAlpha : peakAlpha) : 0
        let blurR: CGFloat = burst
            ? (settled ? cellPx * 1.0 : cellPx * 1.9)
            : 0
        let scale: CGFloat = burst
            ? (settled ? 1.0 : 1.28)
            : 0.85
        RoundedRectangle(cornerRadius: cellPx * 0.26, style: .continuous)
            .fill(OK.toColor(color, opacity: alpha))
            .blur(radius: blurR)
            .scaleEffect(scale)
            .frame(width: cellPx, height: cellPx)
            .onAppear {
                // Phase 1 — sudden flash. Short, punchy ease-out so
                // every cell pops to its peak glow almost instantly.
                withAnimation(.easeOut(duration: 0.22).delay(stagger)) {
                    burst = true
                }
                // Phase 2 — gentle easing to a sustained afterglow.
                // Longer duration + soft ease so the frame reads as a
                // held celebration rather than a flicker.
                withAnimation(.easeOut(duration: 1.2).delay(stagger + 0.22)) {
                    settled = true
                }
            }
    }
}
