//  Top bar: level + tier on the left, mode label or hearts in the center,
//  hamburger button on the right.

import SwiftUI

struct TopBarView: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Left: level + tier
            HStack(spacing: 6) {
                Text("Lv \(game.level)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                let t = game.tier
                Text(t.label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(hexColor(t.colorHex))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(hexColor(t.colorHex).opacity(0.09), in: Capsule())
                if game.showedIncorrect {
                    Text("−1")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center: mode label / hearts
            Group {
                if game.mode == .zen {
                    Text("Zen Mode")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Color(red: 0.27, green: 0.27, blue: 0.27))
                } else {
                    HStack(spacing: 3) {
                        if game.checks > 0 {
                            ForEach(0..<game.checks, id: \.self) { _ in
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))
                            }
                        } else {
                            Text("0 checks")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Right: hamburger
            HStack {
                Spacer(minLength: 0)
                Button {
                    menuOpen.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 34)
                        .foregroundStyle(Color(red: 0.27, green: 0.27, blue: 0.27))
                        .background(menuOpen ? Color.gray.opacity(0.15) : Color.white,
                                    in: Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.82, green: 0.80, blue: 0.78), lineWidth: 1.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
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
