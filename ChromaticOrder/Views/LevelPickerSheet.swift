//  Level-picker sheet. Grid of every zen level the player has
//  unlocked — gated by `challengeMaxLevel` (the highest level
//  reached in challenge mode), since zen is explicitly tied to
//  challenge progression. Tap to jump directly. Only shown in zen
//  mode — challenge is a fresh level-1 run every entry, so there's
//  nothing to pick. Current level is highlighted.

import SwiftUI

struct LevelPickerSheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                let cols = [GridItem(.adaptive(minimum: 64), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(1...max(1, game.challengeMaxLevel), id: \.self) { lv in
                        levelButton(lv)
                    }
                }
                .padding(18)
            }
            .background(Color.black)
            .kromaSheet("level") { dismiss() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func levelButton(_ lv: Int) -> some View {
        let tierInfo = levelTier(lv)
        let tierColor = hexColor(tierInfo.colorHex)
        let isCurrent = lv == game.level
        let shape = RoundedRectangle(cornerRadius: Kroma.Radius.control, style: .continuous)
        Button {
            game.jumpToLevel(lv)
            dismiss()
        } label: {
            let label = VStack(spacing: Kroma.Space.xs) {
                Text("\(lv)")
                    .font(Kroma.font(.headline, .heavy))
                    .foregroundStyle(Color.white.opacity(isCurrent ? 1.0 : 0.85))
                Text(tierInfo.label)
                    .font(Kroma.font(.caption2, .bold))
                    .foregroundStyle(tierColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Kroma.Space.s)
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())

            // The "you are here" tint has no equivalent in KromaSurface
            // (it's puzzle-tier data, not generic chrome), so only the
            // resting state routes through the shared token; the
            // current-level state keeps its bespoke tier-color fill.
            if isCurrent {
                label
                    .background(shape.fill(tierColor.opacity(0.30)))
                    .overlay(shape.stroke(tierColor.opacity(0.75), lineWidth: 1.5))
            } else {
                label
                    .kromaSurface(.control, in: shape)
            }
        }
        .buttonStyle(.kromaControl)
        .accessibilityLabel("level \(lv), \(tierInfo.label)")
        // The ring and fill say "you are here" visually; the selected
        // trait is what says it to VoiceOver.
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
