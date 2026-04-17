//  Bottom strip: instruction text, Check button (challenge mode), and
//  the bank of swatches with Balatro-style sway.

import SwiftUI

struct BankView: View {
    @Bindable var game: GameState

    var body: some View {
        VStack(spacing: 8) {
            Text(instrText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 0.69, green: 0.66, blue: 0.61))

            if game.mode == .challenge, !game.solved {
                Button {
                    game.handleCheck()
                } label: {
                    HStack(spacing: 8) {
                        Text("Check")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill").font(.system(size: 12))
                            Text("\(game.checks)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .opacity(0.85)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .foregroundStyle(.white)
                    .background(game.checks > 0
                                ? Color.accentColor
                                : Color.gray.opacity(0.6),
                                in: Capsule())
                    .shadow(color: Color.accentColor.opacity(game.checks > 0 ? 0.3 : 0),
                            radius: 12, y: 4)
                }
                .disabled(game.checks <= 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let p = game.puzzle {
                        ForEach(Array(p.bank.enumerated()), id: \.element.id) { pair in
                            SwatchView(
                                item: pair.element,
                                index: pair.offset,
                                game: game
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 12)
    }

    private var instrText: String {
        guard let p = game.puzzle else { return "" }
        if game.solved { return "\u{1F3A8} Solved!" }
        if p.bank.isEmpty { return "All placed — check your gradients" }
        if case .bank = game.selection?.kind { return "Tap any empty cell to place" }
        if case .cell = game.selection?.kind { return "Tap another cell to swap, or empty to move" }
        return "Tap or drag a swatch"
    }
}
