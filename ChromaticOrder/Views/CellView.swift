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
                // Empty-cell tint
                if !filled {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.black.opacity(0.05))
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

                // Drop-target outline
                if isDropTarget && !cell.locked {
                    RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: cellPx + 4, height: cellPx + 4)
                }

                // Locked-cell dot
                if cell.locked, filled {
                    let L = placed?.L ?? 0.5
                    let dotColor = L > 0.55
                        ? Color.black.opacity(0.25)
                        : Color.white.opacity(0.5)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 5, height: 5)
                        .frame(width: cellPx, height: cellPx, alignment: .bottomTrailing)
                        .padding(5)
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
                    if filled, !cell.locked, game.dragSource == nil, let placedColor = placed {
                        game.beginDrag(
                            DragSource(kind: .cell(CellIndex(r: r, c: c)), color: placedColor),
                            at: v.location
                        )
                    }
                    if game.dragSource != nil {
                        game.updateDrag(to: v.location, target: game.hitTest(v.location))
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
        game.dropTarget == CellIndex(r: r, c: c)
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
    let phase: Double
    @State private var animate = false

    var body: some View {
        let big = cellPx * 2.0
        RoundedRectangle(cornerRadius: cellPx * 0.26, style: .continuous)
            .fill(Color.clear)
            .frame(width: cellPx, height: cellPx)
            .shadow(color: OK.toColor(color, opacity: animate ? 0.78 : 0.95),
                    radius: animate ? big : big * 1.35, x: 0, y: 0)
            .scaleEffect(animate ? 1 : 1.22)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).delay(phase * 0.22)) {
                    animate = true
                }
            }
    }
}
