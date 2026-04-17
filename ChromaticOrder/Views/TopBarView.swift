//  Top bar: level + tier on the left, mode label or hearts in the center,
//  hamburger button on the right.

import SwiftUI

struct TopBarView: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool

    // Palette for the dark-mode top bar. Primary text is near-white
    // (full white glares), secondary is a softer gray.
    private static let primaryText = Color.white.opacity(0.92)
    private static let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        HStack(spacing: 8) {
            // Left: level + tier
            HStack(spacing: 6) {
                Text("Lv \(game.level)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.primaryText)
                let t = game.tier
                Text(t.label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(hexColor(t.colorHex))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(hexColor(t.colorHex).opacity(0.18), in: Capsule())
                if game.showedIncorrect {
                    Text("−1")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center: mode label / hearts + score
            Group {
                if game.mode == .zen {
                    Text("Zen Mode")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Self.primaryText)
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            if game.checks > 0 {
                                ForEach(0..<game.checks, id: \.self) { _ in
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                                }
                            } else {
                                Text("0 \u{2665}")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Self.secondaryText)
                            }
                        }
                        Text("\(game.score)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Self.primaryText)
                            .monospacedDigit()
                    }
                }
            }

            // Right: hamburger — light outline capsule on dark bg.
            HStack {
                Spacer(minLength: 0)
                Button {
                    menuOpen.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 34)
                        .foregroundStyle(Self.primaryText)
                        .background(menuOpen
                                    ? Color.white.opacity(0.18)
                                    : Color.white.opacity(0.08),
                                    in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

func hexColor(_ hex: String) -> Color {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 {
        h = h.map { "\($0)\($0)" }.joined()
    }
    var rgb: UInt64 = 0
    Scanner(string: h).scanHexInt64(&rgb)
    let r = Double((rgb >> 16) & 0xff) / 255
    let g = Double((rgb >> 8) & 0xff) / 255
    let b = Double(rgb & 0xff) / 255
    return Color(red: r, green: g, blue: b)
}
