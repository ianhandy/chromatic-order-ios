//  A single bank slot. Renders the swatch when the slot is occupied,
//  or an empty slot indicator when not. Reports its global frame so
//  GameState.hitTest can target it for drag-drops. Handles taps and
//  drags on its own contents.

import SwiftUI

struct BankSlotView: View {
    let slot: Int
    let size: CGFloat
    @Bindable var game: GameState
    @State private var sway: CGFloat = 0

    var body: some View {
        let item: BankItem? = {
            guard let p = game.puzzle, slot < p.bank.count else { return nil }
            return p.bank[slot]
        }()
        let radius = size * 0.28

        ZStack {
            // Empty-slot placeholder — same footprint as a swatch so the
            // grid layout never shifts. Light dashed outline hints that
            // the slot accepts drops.
            if item == nil {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(isDropTarget ? 0.03 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                Color.black.opacity(isDropTarget ? 0.12 : 0.06),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                            )
                    )
                    .frame(width: size, height: size)
            }

            // Drop-target flash tint (fills the slot in the held color
            // when magnetism picks this slot — no outline).
            if isDropTarget, let held = game.heldColor {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OK.toColor(held, opacity: 0.9))
                    .frame(width: size, height: size)
                    .transition(.opacity.animation(.easeInOut(duration: 0.22)))
            }

            // Live swatch (when this slot holds one)
            if let item {
                SwatchChip(
                    color: item.color,
                    size: size,
                    radius: radius,
                    picked: isPicked,
                    swayPhase: sway,
                    animateSway: !isPicked && !isDragSource && !game.reduceMotion
                )
                .opacity(isDragSource ? 0.15 : 1)
            }
        }
        .frame(width: size, height: size)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BankSlotFramesKey.self,
                    value: [slot: geo.frame(in: .global)]
                )
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            game.tapSlot(slot)
        }
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { v in
                    // Only empty the slot temporarily while dragging —
                    // beginDrag stores the color; the actual bank
                    // mutation happens on endDrag via placeSlotIntoCell
                    // or moveSlotToSlot.
                    if let item, game.dragSource == nil {
                        game.beginDrag(
                            DragSource(kind: .bank(slot), color: item.color),
                            at: v.location
                        )
                    }
                    if game.dragSource != nil {
                        game.updateDrag(to: v.location)
                    }
                }
                .onEnded { _ in
                    if case .bank(let s) = game.dragSource?.kind, s == slot {
                        game.endDrag(moved: true)
                    }
                }
        )
        .onAppear {
            guard !game.reduceMotion else { return }
            let dur = 4.0 + Double((slot * 37) % 25) / 10.0
            withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true)
                          .delay(-Double((slot * 13) % 40) / 10.0)) {
                sway = 1
            }
        }
    }

    private var isPicked: Bool {
        if case .bank(let s) = game.selection?.kind { return s == slot }
        return false
    }

    private var isDragSource: Bool {
        if case .bank(let s) = game.dragSource?.kind { return s == slot }
        return false
    }

    private var isDropTarget: Bool {
        if case .slot(let s) = game.dropTarget { return s == slot }
        return false
    }
}

// Visual-only swatch used inside a slot. Doesn't know about state.
private struct SwatchChip: View {
    let color: OKLCh
    let size: CGFloat
    let radius: CGFloat
    let picked: Bool
    let swayPhase: CGFloat
    let animateSway: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(color))
            .frame(width: size, height: size)
            .shadow(color: picked ? .black.opacity(0.18) : .black.opacity(0.12),
                    radius: picked ? 10 : 4, y: picked ? 4 : 2)
            .scaleEffect(picked ? 1.12 : 1)
            .offset(
                x: animateSway ? sin(swayPhase * .pi * 2) * 1.6 : 0,
                y: picked
                    ? -6
                    : (animateSway ? -abs(sin(swayPhase * .pi * 2)) * 2.5 : 0)
            )
            .rotationEffect(.degrees(animateSway ? sin(swayPhase * .pi * 2) * 1.1 : 0))
            .animation(.easeOut(duration: 0.38), value: picked)
    }
}
