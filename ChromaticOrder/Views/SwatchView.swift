//  A single bank slot. Renders the swatch when the slot is occupied,
//  or an empty slot indicator when not. Reports its global frame so
//  GameState.hitTest can target it for drag-drops. Handles taps and
//  drags on its own contents.

import SwiftUI

struct BankSlotView: View {
    let slot: Int
    let size: CGFloat
    @Bindable var game: GameState

    var body: some View {
        let item: BankItem? = {
            guard let p = game.puzzle, slot < p.bank.count else { return nil }
            return p.bank[slot]
        }()
        let radius = size * 0.28
        let returning = game.bankReturnSlot == slot
        let reduceMotion = game.shouldReduceMotion

        ZStack {
            // Empty-slot placeholder — same footprint as a swatch so the
            // grid layout never shifts. Light dashed outline hints that
            // the slot accepts drops.
            if item == nil {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(isDropTarget ? 0.10 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isDropTarget ? 0.35 : 0.18),
                                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                            )
                    )
                    .frame(width: size, height: size)
            }

            // Drop-target flash tint (fills the slot in the held color
            // when magnetism picks this slot — no outline).
            if isDropTarget, let held = game.heldColor.map(game.display) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OK.toColor(held, opacity: 0.9))
                    .frame(width: size, height: size)
                    .transition(.opacity.animation(.easeInOut(duration: 0.22)))
            }

            // Live swatch (when this slot holds one)
            if let item {
                SwatchChip(
                    // Display color only. The drag below carries
                    // `item.color`, the real one, so what lands in a
                    // cell is unaffected by the testing filter.
                    color: game.display(item.color),
                    size: size,
                    radius: radius,
                    picked: isPicked
                )
                .opacity(isDragSource ? 0.15 : 1)
            }

            if game.hintedBankSlot == slot {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 3)
                    .frame(width: size, height: size)
                    .allowsHitTesting(false)
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
        // A rejected bank drag never moved the item in state: animate the
        // original slot itself so it visibly compresses, overshoots, and
        // settles back in place. Reduce Motion keeps the exact same state
        // transition without the animated bounce.
        .keyframeAnimator(
            initialValue: 1.0,
            trigger: game.bankReturnAnimationID
        ) { content, scale in
            content.scaleEffect(returning && !reduceMotion ? scale : 1)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.82, duration: 0.08)
                SpringKeyframe(1.13, duration: 0.16, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.22, spring: .smooth)
            }
        }
        // Unified gesture — tap vs drag decided by translation so a
        // drag release doesn't also fire tapSlot (which caused stray
        // swatch-picks on liftoff).
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    guard moved >= 5 else { return }
                    // Nothing picks up once the puzzle is solved — the
                    // board is frozen for the completion animation.
                    if let item, game.dragSource == nil, !game.solved {
                        game.beginDrag(
                            DragSource(kind: .bank(slot), color: item.color),
                            at: v.location
                        )
                    }
                    if game.dragSource != nil {
                        game.updateDrag(to: v.location)
                    }
                }
                .onEnded { v in
                    let moved = hypot(v.translation.width, v.translation.height)
                    if case .bank(let s) = game.dragSource?.kind, s == slot {
                        game.endDrag(moved: true)
                    } else if moved < 5, game.dragSource == nil {
                        game.tapSlot(slot)
                    }
                }
        )
        // The slot is driven entirely by a DragGesture, which VoiceOver
        // cannot perform — so it needs an explicit action as well as a
        // name. "Picked up" is the same fact the swatch's lift and
        // shadow show sighted players.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item == nil
                            ? "empty slot \(slot + 1)"
                            : "swatch \(slot + 1)")
        .accessibilityValue(game.hintedBankSlot == slot
                            ? "hinted"
                            : (isPicked ? "picked up" : ""))
        .accessibilityAddTraits(item == nil ? [] : .isButton)
        .accessibilityAction {
            game.tapSlot(slot)
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
//
// There used to be an idle "sway" here: every slot started a
// repeatForever animation on mount that drove `sin(phase * 2π)` inside
// an `.offset`. SwiftUI interpolates the offset between the values the
// body produced at each end of the animation, and both ends of a full
// sine period are zero — so the sway rendered nothing while keeping one
// never-ending animation alive per bank slot. Removed; the chip looks
// exactly as it did.
private struct SwatchChip: View {
    let color: OKLCh
    let size: CGFloat
    let radius: CGFloat
    let picked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(color))
            .frame(width: size, height: size)
            .shadow(color: picked ? .black.opacity(0.18) : .black.opacity(0.12),
                    radius: picked ? 10 : 4, y: picked ? 4 : 2)
            .scaleEffect(picked ? 1.12 : 1)
            .offset(y: picked ? -6 : 0)
            .animation(.easeOut(duration: 0.38), value: picked)
    }
}
