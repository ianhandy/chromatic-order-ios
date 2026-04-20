//  Top bar: level + tier on the left, mode label or hearts in the center,
//  hamburger button on the right.

import SwiftUI

struct TopBarView: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool
    @State private var levelPickerOpen: Bool = false

    // Palette for the dark-mode top bar. Primary text is near-white
    // (full white glares), secondary is a softer gray.
    private static let primaryText = Color.white.opacity(0.92)
    private static let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Left: level + tier (top row), challenge score below.
            // In zen mode the whole "Lv X + tier" cluster is
            // tappable and opens the level-picker sheet so the
            // player can jump to any earlier level they've reached.
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    guard game.mode == .zen else { return }
                    levelPickerOpen = true
                } label: {
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
                        if game.mode == .zen {
                            Image(systemName: "chevron.down.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Self.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(game.mode != .zen)
                if game.mode == .challenge {
                    Text("\(game.score) pts")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.secondaryText)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center column: mode label / hearts on top, then a
            // shared timer + moves row so the player can see pace
            // and efficiency at a glance. Timer hides when the a11y
            // toggle is off — the internal clock still runs for
            // leaderboard submissions.
            VStack(spacing: 2) {
                if game.mode == .zen {
                    Text("Zen Mode")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(Self.primaryText)
                } else {
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
                }
                // Timer + moves readout. Updates once per second via
                // TimelineView so SwiftUI doesn't re-render the whole
                // top bar mid-interaction. `game.solved` freezes the
                // timer at the solve time so the player can see it.
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    HStack(spacing: 8) {
                        if game.timerVisible {
                            Text(formatElapsed(game.timeSpentSec))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Self.secondaryText)
                        }
                        Text("\(game.moveCount) mv")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Self.secondaryText)
                    }
                }
            }

            // Right: favorite star + hamburger. Star saves the
            // current puzzle to the favorites gallery; tap again to
            // remove it. Disabled while the generator is still
            // producing the puzzle so the user can't favorite nil.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                let favorited = game.currentFavoriteURL != nil
                Button {
                    game.toggleFavorite()
                } label: {
                    Image(systemName: favorited ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 34)
                        .foregroundStyle(favorited
                                          ? Color(red: 1.00, green: 0.83, blue: 0.22)
                                          : Self.primaryText)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                }
                .disabled(game.puzzle == nil || game.generating)
                Button {
                    GlassyAudio.shared.playBloom()
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
        .sheet(isPresented: $levelPickerOpen) {
            LevelPickerSheet(game: game)
        }
    }
}

/// "0:42" style mm:ss formatter for the in-game timer. Rolls over
/// to "h:mm:ss" for long zen sessions so pre-caffeine play doesn't
/// silently wrap past 60 minutes.
private func formatElapsed(_ s: Int) -> String {
    let seconds = max(0, s)
    let m = seconds / 60
    let sec = seconds % 60
    if m >= 60 {
        let h = m / 60
        let mm = m % 60
        return String(format: "%d:%02d:%02d", h, mm, sec)
    }
    return String(format: "%d:%02d", m, sec)
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
