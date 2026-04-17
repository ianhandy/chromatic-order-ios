//  Single bank swatch — static color chip with Balatro-style idle sway
//  when not picked / dragging.

import SwiftUI

struct SwatchView: View {
    let item: BankItem
    let index: Int
    @Bindable var game: GameState
    @State private var sway: CGFloat = 0

    var body: some View {
        let px: CGFloat = 48
        let radius: CGFloat = px * 0.28
        let isPicked: Bool = {
            if case .bank(let uid) = game.selection?.kind { return uid == item.id }
            return false
        }()
        let isDragging: Bool = {
            if case .bank(let uid) = game.dragSource?.kind { return uid == item.id }
            return false
        }()

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(item.color))
            .frame(width: px, height: px)
            .shadow(color: isPicked ? .black.opacity(0.18) : .black.opacity(0.12),
                    radius: isPicked ? 10 : 4, y: isPicked ? 4 : 2)
            .opacity(isDragging ? 0.15 : 1)
            .scaleEffect(isPicked ? 1.12 : 1)
            .offset(
                x: shouldSway(isPicked: isPicked, isDragging: isDragging) ? sin(sway * .pi * 2) * 1.6 : 0,
                y: isPicked
                    ? -6
                    : (shouldSway(isPicked: isPicked, isDragging: isDragging) ? -abs(sin(sway * .pi * 2)) * 2.5 : 0)
            )
            .rotationEffect(
                .degrees(shouldSway(isPicked: isPicked, isDragging: isDragging)
                         ? sin(sway * .pi * 2) * 1.1 : 0)
            )
            .animation(.easeOut(duration: 0.38), value: isPicked)
            .onAppear {
                guard !game.reduceMotion else { return }
                let dur = 4.0 + Double((index * 37) % 25) / 10.0
                // Phase offset via negative animation delay.
                withAnimation(.easeInOut(duration: dur).repeatForever(autoreverses: true)
                              .delay(-Double((index * 13) % 40) / 10.0)) {
                    sway = 1
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                game.tapBank(uid: item.id)
            }
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { v in
                        if game.dragSource == nil {
                            game.beginDrag(
                                DragSource(kind: .bank(item.id), color: item.color),
                                at: v.location
                            )
                        }
                        game.updateDrag(to: v.location, target: game.hitTest(v.location))
                    }
                    .onEnded { _ in
                        if case .bank(let uid) = game.dragSource?.kind, uid == item.id {
                            game.endDrag(moved: true)
                        }
                    }
            )
    }

    private func shouldSway(isPicked: Bool, isDragging: Bool) -> Bool {
        !isPicked && !isDragging && !game.reduceMotion
    }
}
