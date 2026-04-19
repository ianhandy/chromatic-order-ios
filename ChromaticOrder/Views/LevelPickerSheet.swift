//  Level-picker sheet. Grid of every zen level the player has
//  reached so far; tap to jump directly there. Only shown in zen
//  mode — challenge is a fresh level-1 run every entry, so there's
//  nothing to pick. Current level is highlighted so the player
//  always knows where they're starting from.

import SwiftUI

struct LevelPickerSheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                let cols = [GridItem(.adaptive(minimum: 64), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(1...max(1, game.zenMaxLevel), id: \.self) { lv in
                        levelButton(lv)
                    }
                }
                .padding(18)
            }
            .background(Color.black)
            .navigationTitle("change level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func levelButton(_ lv: Int) -> some View {
        let tierInfo = levelTier(lv)
        let tierColor = hexColor(tierInfo.colorHex)
        let isCurrent = lv == game.level
        Button {
            game.jumpToLevel(lv)
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Text("\(lv)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(isCurrent ? 1.0 : 0.85))
                Text(tierInfo.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(tierColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent
                          ? tierColor.opacity(0.30)
                          : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isCurrent
                            ? tierColor.opacity(0.75)
                            : Color.white.opacity(0.14),
                            lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
