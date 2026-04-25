//  Top bar: level + tier on the left, mode label or hearts in the center,
//  hamburger button on the right.

import SwiftUI

/// Lifecycle of the celebratory heart that flies from the "perfect"
/// banner into the top-bar hearts row on a perfect challenge-mode
/// solve. Drives matchedGeometryEffect + wave trigger sequencing.
///   idle     — nothing showing
///   onBanner — big heart rendered next to the "perfect" text
///   flying   — matched-geometry transition to the top-bar row
///   landed   — heart has arrived; wave animation plays
enum PerfectHeartStage { case idle, onBanner, flying, landed }

struct TopBarView: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool
    /// Shared matched-geometry namespace so the perfect-heart flight
    /// can transition between ContentView's banner and this view's
    /// hearts row. ContentView owns the @Namespace; this view just
    /// consumes the ID.
    let perfectHeartNS: Namespace.ID
    /// Current stage of the perfect-heart choreography. Drives whether
    /// the "flying target" matched-geometry heart renders at the end
    /// of the row (during .flying / .landed) or not (idle / onBanner).
    let perfectHeartStage: PerfectHeartStage
    /// Bump counter from ContentView — each increment triggers a
    /// staggered per-heart scale-bump wave across the existing hearts.
    let heartWaveTick: Int
    @State private var levelPickerOpen: Bool = false

    // Palette for the dark-mode top bar. Primary text is near-white
    // (full white glares), secondary is a softer gray.
    private static let primaryText = Color.white.opacity(0.92)
    private static let secondaryText = Color.white.opacity(0.6)

    // Button sizing: the three top-row affordances (level chip,
    // favorite, hamburger) all share this height so they sit on a
    // single baseline with the center "zen" / "today" wordmark.
    private static let buttonHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 8) {
            // Primary row: three buttons + center mode label, all
            // vertically centered on one axis. HStack(.center)
            // aligns each child's center to the row's center, so
            // the 68pt buttons and the 34pt "zen" wordmark share a
            // midline instead of drifting apart.
            HStack(alignment: .center, spacing: 10) {
                levelChip
                Spacer(minLength: 0)
                centerModeLabel
                Spacer(minLength: 0)
                rightButtons
            }

            // Secondary row: one readout under each primary-row
            // element so timer / moves / points each sit directly
            // under the thing they're associated with (chip / zen /
            // right buttons). Same HStack(.center) alignment keeps
            // the three columns on one baseline.
            HStack(alignment: .top, spacing: 10) {
                leftStat
                    .frame(maxWidth: .infinity, alignment: .leading)
                centerStat
                    .frame(maxWidth: .infinity, alignment: .center)
                rightStat
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .sheet(isPresented: $levelPickerOpen) {
            LevelPickerSheet(game: game)
        }
    }

    // MARK: – Top row

    @ViewBuilder
    private var levelChip: some View {
        if game.mode != .daily {
            let t = game.tier
            Button {
                guard game.mode == .zen else { return }
                levelPickerOpen = true
            } label: {
                HStack(spacing: 4) {
                    Text("Lv \(game.level)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(hexColor(t.colorHex))
                    if game.mode == .zen {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Self.secondaryText)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: Self.buttonHeight)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(game.mode != .zen)
            // Publish the chip's bounds into the shared tutorial
            // anchor bag so the zen-intro tooltip overlay can draw a
            // pointer line from itself directly to this chip without
            // hard-coding the chip's screen position.
            .transformAnchorPreference(
                key: TutorialAnchorsKey.self,
                value: .bounds
            ) { value, anchor in
                value["chip"] = anchor
            }
        } else {
            // Daily mode: static "daily" chip in the same slot the
            // level chip would take, so the top-left balance matches
            // zen/challenge and the player has a clear mode marker.
            // Not interactive — daily's level is fixed per date.
            Text("daily")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.primaryText)
                .padding(.horizontal, 12)
                .frame(height: Self.buttonHeight)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var centerModeLabel: some View {
        // Custom-loaded puzzles (community / gallery / favorites that
        // ship with a name) override the mode wordmark so the player
        // sees the level's title instead of the generic "zen" label.
        // Long titles get a gentle width cap + truncation so the
        // top-bar layout stays balanced.
        if let title = game.customTitle, !title.isEmpty {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220)
        } else {
            switch game.mode {
            case .zen:
                Text("zen")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.primaryText)
            case .daily:
                Text("today")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Self.primaryText)
            case .challenge:
                heartsRow
            }
        }
    }

    /// Individual items rendered by the hearts-row ForEach. A flat
    /// array of these (instead of a ForEach + trailing conditional
    /// `+N` Text) was the simplest fix for a SwiftUI diffing quirk
    /// where the trailing branch sometimes failed to render once the
    /// heart count climbed past 5.
    private enum HeartItem: Hashable, Identifiable {
        case zero
        case heart(Int)      // index into the row (0..<5)
        case overflow(Int)   // how many hearts beyond 5
        var id: String {
            switch self {
            case .zero: return "zero"
            case .heart(let i): return "h\(i)"
            case .overflow(let n): return "o\(n)"
            }
        }
    }

    private var heartRowItems: [HeartItem] {
        let checks = max(0, game.checks)
        if checks == 0 { return [.zero] }
        let displayed = min(checks, 5)
        let extra = max(0, checks - 5)
        var items: [HeartItem] = (0..<displayed).map { HeartItem.heart($0) }
        if extra > 0 { items.append(.overflow(extra)) }
        return items
    }

    @ViewBuilder
    private var heartsRow: some View {
        let heartRed = Color(red: 1.0, green: 0.4, blue: 0.4)
        HStack(spacing: 4) {
            ForEach(heartRowItems) { item in
                switch item {
                case .zero:
                    Text("0 \u{2665}")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.secondaryText)
                        .transition(.opacity)
                case .heart(let idx):
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(heartRed)
                        .phaseAnimator([1.0, 1.35, 1.0],
                                       trigger: heartWaveTick) { content, s in
                            content.scaleEffect(s)
                        } animation: { _ in
                            .spring(response: 0.30,
                                    dampingFraction: 0.55)
                                .delay(Double(idx) * 0.07)
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal: .scale(scale: 0.4).combined(with: .opacity)
                        ))
                case .overflow(let n):
                    Text("+\(n)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(heartRed)
                        .fixedSize()
                        .accessibilityLabel("plus \(n) more")
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .id("overflow-\(n)")
                }
            }
            // Flying-in heart from the "perfect" banner. Sits at the
            // end of the row during `.flying`; on `.landed` the
            // ContentView promotes it to a real heart in
            // `game.checks` so the row keeps showing it.
            if perfectHeartStage == .flying {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(heartRed)
                    .matchedGeometryEffect(
                        id: "perfectHeart",
                        in: perfectHeartNS,
                        isSource: false
                    )
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.72),
                   value: heartRowItems)
    }

    @ViewBuilder
    private var rightButtons: some View {
        HStack(spacing: 8) {
            let favorited = game.currentFavoriteURL != nil
            Button {
                game.toggleFavorite()
            } label: {
                Image(systemName: favorited ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: Self.buttonHeight)
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
                    .frame(width: 38, height: Self.buttonHeight)
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
    }

    // MARK: – Second row

    /// Under the level chip: running timer stacked above the move
    /// count. Timer hides when the a11y toggle is off (the internal
    /// clock still ticks for leaderboard submissions).
    @ViewBuilder
    private var leftStat: some View {
        VStack(alignment: .leading, spacing: 2) {
            if game.timerVisible {
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    Text(formatElapsed(game.timeSpentSec))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.secondaryText)
                }
            }
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text("\(game.moveCount) mv")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.secondaryText)
            }
        }
    }

    /// Center column is intentionally empty now that moves moved to
    /// the left column; kept as a spacer so the three-column layout
    /// keeps the right-side points aligned.
    @ViewBuilder
    private var centerStat: some View {
        EmptyView()
    }

    /// Right column is intentionally empty — the old challenge-score
    /// readout was removed when the points system went away.
    @ViewBuilder
    private var rightStat: some View {
        EmptyView()
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
