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
    /// Optional handler invoked when the player taps the back arrow
    /// shown in place of the level chip while playing a custom puzzle
    /// loaded from the gallery. Caller is responsible for closing the
    /// game screen and restoring the gallery sheet (see ContentView).
    var onBackToGallery: (() -> Void)? = nil
    @State private var levelPickerOpen: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Past the accessibility sizes the top bar stops being one row.
    private var usesStackedChrome: Bool { dynamicTypeSize.isAccessibilitySize }

    // Palette for the dark-mode top bar. Primary text is near-white
    // (full white glares), secondary is a softer gray.
    private static let primaryText = Color.white.opacity(0.92)
    private static let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        VStack(alignment: .leading, spacing: Kroma.Space.xs) {
            // Where you are on the left, what you're playing in the
            // middle, what you can do on the right. The chip and the
            // buttons are load-bearing — one says where you are, the other
            // is the only way out — so they get the width they ask for and
            // the wordmark in the middle is what gives. Without the
            // priorities, an accessibility text size
            // grew the wordmark until the two right-hand buttons were
            // squeezed past zero spacing and drew on top of each other.
            HStack(alignment: .center, spacing: Kroma.Space.s) {
                levelChip
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if !usesStackedChrome {
                    centerModeLabel
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                }
                rightButtons
                    .layoutPriority(1)
            }

            // At an accessibility text size the chip and the two buttons
            // already fill the row, and leaving the wordmark between them
            // crushed it to a one-letter column reading vertically. It
            // drops to its own full-width line instead — hiding it would
            // take the label away from exactly the players who turned the
            // text size up to read it.
            if usesStackedChrome {
                centerModeLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Progress readout, under the chip it belongs to. It used
            // to be a three-column row with two permanently empty
            // columns holding the layout open, printed at the same
            // 20pt weight as the mode wordmark — so a move counter
            // competed with the name of the mode. It's status; it now
            // reads as status.
            progressReadout
        }
        .padding(.top, Kroma.Space.s)
        .padding(.bottom, Kroma.Space.s)
        .sheet(isPresented: $levelPickerOpen) {
            LevelPickerSheet(game: game)
        }
    }

    // MARK: – Top row

    @ViewBuilder
    private var levelChip: some View {
        // Custom puzzles loaded from the Gallery override every mode's
        // chip — the player came in via a specific entry, so the slot
        // surfaces a return arrow back to that entry instead of the
        // mode-specific level / "daily" affordance. The chevron text
        // gives a hint without reserving extra horizontal space.
        if let index = game.campaignIndex {
            // Campaign: the chip carries the level's place in the campaign
            // rather than a zen tier, and doesn't open the zen level picker
            // (that would drop the player out of the authored run).
            chipText("\(index)/\(CampaignCatalog.count)")
                .foregroundStyle(Self.primaryText)
                .kromaSurface(.control)
                .accessibilityLabel("campaign level \(index) of \(CampaignCatalog.count)")
        } else if game.cameFromGallery, let onBack = onBackToGallery {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(Kroma.font(.headline, .semibold))
                    .foregroundStyle(Self.primaryText)
                    .frame(minWidth: 38)
                    .frame(minHeight: Kroma.Metrics.chromeControl)
                    .padding(.horizontal, Kroma.Space.s)
                    .kromaSurface(.control)
                    .kromaHitTarget()
            }
            .buttonStyle(.kromaControl)
            .accessibilityLabel("back to gallery")
        } else if game.mode != .daily {
            let t = game.tier
            // Only zen can change level; in challenge the chip is a
            // readout, so it isn't dressed as a button there.
            if game.mode == .zen {
                Button { levelPickerOpen = true } label: {
                    HStack(spacing: Kroma.Space.xs) {
                        Text("Lv \(game.level)")
                            .font(Kroma.font(.subheadline, .heavy))
                            .foregroundStyle(hexColor(t.colorHex))
                        Image(systemName: "chevron.down")
                            .font(Kroma.font(.caption2, .bold))
                            .foregroundStyle(Self.secondaryText)
                    }
                    .padding(.horizontal, Kroma.Space.m)
                    .padding(.vertical, Kroma.Space.s)
                    .frame(minHeight: Kroma.Metrics.chromeControl)
                    .kromaSurface(.control)
                    .kromaHitTarget()
                }
                .buttonStyle(.kromaControl)
                .accessibilityLabel("level \(game.level), \(t.label)")
                .accessibilityHint("change level")
                // Publish the chip's global frame into the shared
                // tutorial frame bag so the zen-intro tooltip overlay
                // can draw a pointer line + spotlight hole directly
                // around this chip without hard-coding its position.
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TutorialTargetFramesKey.self,
                            value: ["chip": geo.frame(in: .global)]
                        )
                    }
                }
            } else {
                chipText("Lv \(game.level)")
                    .foregroundStyle(hexColor(t.colorHex))
                    .kromaSurface(.control)
                    .accessibilityLabel("level \(game.level), \(t.label)")
            }
        } else {
            // Daily: a fixed marker in the slot the level chip would
            // take, so the top-left balance matches the other modes.
            chipText("daily")
                .foregroundStyle(Self.primaryText)
                .kromaSurface(.control)
                // Same frame contract as the zen chip, for the
                // daily-intro tutorial's pointer + spotlight.
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: TutorialTargetFramesKey.self,
                            value: ["dailyChip": geo.frame(in: .global)]
                        )
                    }
                }
        }
    }

    /// A non-interactive top-bar chip. Grows with Dynamic Type instead
    /// of clipping inside a fixed 34pt capsule.
    private func chipText(_ text: String) -> some View {
        Text(text)
            .font(Kroma.font(.subheadline, .heavy))
            // "1/200" is one token. Left to wrap, an accessibility text
            // size broke it across two lines as "1/2" over "00", which
            // reads as a different number entirely.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Kroma.Space.m)
            .padding(.vertical, Kroma.Space.s)
            .frame(minHeight: Kroma.Metrics.chromeControl)
    }

    @ViewBuilder
    private var centerModeLabel: some View {
        // Custom-loaded puzzles (community / gallery / favorites that
        // ship with a name) override the mode wordmark so the player
        // sees the level's title instead of the generic "zen" label.
        // Long titles get a gentle width cap + truncation so the
        // top-bar layout stays balanced.
        if let index = game.campaignIndex {
            // Campaign: the slot the other modes use for their wordmark
            // carries where the player is in the ladder. The chip beside it
            // already says "37/200"; this says which chapter that lands in,
            // which is the thing that changes what the board asks of you.
            Text(campaignChapterTitle(index))
                .font(Kroma.font(.title3, .heavy))
                .foregroundStyle(Self.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: usesStackedChrome ? .infinity : 200,
                       alignment: usesStackedChrome ? .leading : .center)
                // The chip next to it already announces "campaign level 37
                // of 200", so this only has to name the chapter.
                .accessibilityLabel("chapter, \(campaignChapterTitle(index))")
                .accessibilityAddTraits(.isHeader)
        } else if let title = game.customTitle, !title.isEmpty {
            Text(title)
                .font(Kroma.font(.title3, .heavy))
                .foregroundStyle(Self.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240)
                .accessibilityAddTraits(.isHeader)
        } else {
            switch game.mode {
            case .zen:
                Text("zen")
                    .font(Kroma.font(.title2, .heavy))
                    .foregroundStyle(Self.primaryText)
                    .accessibilityAddTraits(.isHeader)
            case .daily:
                Text("today")
                    .font(Kroma.font(.title2, .heavy))
                    .foregroundStyle(Self.primaryText)
                    .accessibilityAddTraits(.isHeader)
            case .challenge:
                heartsRow
            }
        }
    }

    /// Chapter the given campaign level sits in, lowercased to match the
    /// rest of the chrome. Falls back to the plain mode wordmark's register
    /// if the catalog can't place the index, which it only can't when the
    /// bundled campaign failed to load at all.
    private func campaignChapterTitle(_ index: Int) -> String {
        CampaignCatalog.chapter(containing: index)?.title.lowercased() ?? "campaign"
    }

    /// Individual items rendered by the hearts-row ForEach. A flat
    /// array of these (instead of a ForEach + trailing conditional
    /// `+N` Text) was the simplest fix for a SwiftUI diffing quirk
    /// where the trailing branch sometimes failed to render once the
    /// heart count climbed past 5.
    private enum HeartItem: Hashable, Identifiable {
        case zero
        case heart(Int)      // individual heart at index (0..<threshold)
        case counter(Int)    // single heart merged with the total count
        var id: String {
            switch self {
            case .zero: return "zero"
            case .heart(let i): return "h\(i)"
            // Constant id (count excluded) so the counter view keeps its
            // identity as the number changes — that's what lets the
            // digit roll gently via `.contentTransition(.numericText)`
            // instead of being torn down and popped back in.
            case .counter: return "counter"
            }
        }
    }

    /// Above this many hearts the row stops drawing individual icons and
    /// switches to a single heart fused with a count that rolls up/down.
    private static let heartIconCap = 5

    private var heartRowItems: [HeartItem] {
        let checks = max(0, game.checks)
        if checks == 0 { return [.zero] }
        if checks <= Self.heartIconCap {
            return (0..<checks).map { HeartItem.heart($0) }
        }
        return [.counter(checks)]
    }

    @ViewBuilder
    private var heartsRow: some View {
        let heartRed = Color(red: 1.0, green: 0.4, blue: 0.4)
        HStack(spacing: Kroma.Space.xs) {
            ForEach(heartRowItems) { item in
                switch item {
                case .zero:
                    Text("0 \u{2665}")
                        .font(Kroma.font(.subheadline, .bold))
                        .foregroundStyle(Self.secondaryText)
                        .transition(.opacity)
                case .heart(let idx):
                    Image(systemName: "heart.fill")
                        .font(Kroma.font(.body, .regular))
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
                case .counter(let n):
                    // One heart fused directly with the count. The
                    // number rolls gently to its next value via the
                    // numeric content transition rather than popping.
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(Kroma.font(.body, .regular))
                            .foregroundStyle(heartRed)
                            .phaseAnimator([1.0, 1.35, 1.0],
                                           trigger: heartWaveTick) { content, s in
                                content.scaleEffect(s)
                            } animation: { _ in
                                .spring(response: 0.30, dampingFraction: 0.55)
                            }
                        Text("\(n)")
                            .font(Kroma.font(.body, .heavy))
                            .foregroundStyle(heartRed)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(n)))
                            .fixedSize()
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(n) hearts")
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            // Flying-in heart from the "perfect" banner. Sits at the
            // end of the row during `.flying`; on `.landed` the
            // ContentView promotes it to a real heart in
            // `game.checks` so the row keeps showing it.
            if perfectHeartStage == .flying {
                Image(systemName: "heart.fill")
                    .font(.body)
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
        HStack(spacing: Kroma.Space.s) {
            if game.canSaveCurrentPuzzle {
                let _ = game.campaignBookmarkRevision
                let favorited = game.isCurrentPuzzleSaved
                Button {
                    game.toggleCurrentPuzzleSaved()
                } label: {
                    Image(systemName: favorited ? "star.fill" : "star")
                        .font(Kroma.font(.subheadline, .semibold))
                        .frame(minWidth: 38)
                        .frame(minHeight: Kroma.Metrics.chromeControl)
                        .foregroundStyle(favorited
                                          ? Color(red: 1.00, green: 0.83, blue: 0.22)
                                          : Self.primaryText)
                        .kromaSurface(.control)
                        .kromaHitTarget()
                }
                .buttonStyle(.kromaControl)
                .disabled(game.puzzle == nil || game.generating)
                // Filled vs outline already distinguishes the two states
                // visually; this is what carries it to VoiceOver and to
                // anyone who can't read the fill.
                .accessibilityLabel(game.campaignIndex == nil ? "favorite" : "bookmark")
                .accessibilityValue(favorited ? "on" : "off")
            }

            Button {
                menuOpen.toggle()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(Kroma.font(.body, .semibold))
                    .frame(minWidth: 38)
                    .frame(minHeight: Kroma.Metrics.chromeControl)
                    .foregroundStyle(Self.primaryText)
                    .kromaSurface(menuOpen ? .controlActive : .control)
                    .kromaHitTarget()
            }
            .buttonStyle(.kromaControl)
            // Without this the symbol's own description wins and
            // VoiceOver announces the menu button as "Drag".
            .accessibilityLabel("menu")
            .accessibilityValue(menuOpen ? "expanded" : "collapsed")
        }
    }

    // MARK: – Progress readout

    /// Elapsed time and moves, under the chip they describe. The timer
    /// hides when the player has turned it off — the internal clock
    /// keeps running for leaderboard submissions either way.
    @ViewBuilder
    private var progressReadout: some View {
        HStack(spacing: Kroma.Space.s) {
            if game.timerVisible {
                // `timeSpentSec` is derived from a start date, so it
                // needs a clock to redraw. `moveCount` is observed
                // state and doesn't — it used to sit inside a second
                // one-second timeline redrawing for nothing.
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    // The separator rides on the timer rather than sitting
                    // between the two as its own view, so VoiceOver never
                    // has a stray "dot" element to step through. Two
                    // monospaced numbers with only a space between them
                    // ran together at large text sizes — "0:50" and
                    // "0 moves" read as "0:500 moves".
                    Text("\(formatElapsed(game.timeSpentSec)) ·")
                        .accessibilityLabel("time \(formatElapsed(game.timeSpentSec))")
                }
            }
            // Singular on the first placement of every puzzle, so this
            // read "1 moves" constantly before the pluralization.
            Text("\(game.moveCount) move\(game.moveCount == 1 ? "" : "s")")
                .accessibilityLabel("\(game.moveCount) move\(game.moveCount == 1 ? "" : "s")")
        }
        .font(Kroma.monoFont(.footnote, .semibold))
        .foregroundStyle(Self.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
