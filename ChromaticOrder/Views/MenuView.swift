//  Main menu — black backdrop with a few "palette strips" sliding in
//  from the edges at a time. Each strip is a short row/column of
//  OKLCh swatches that enters from one edge, travels across the
//  screen, and fades out on the far side. Directions and timing are
//  staggered: one strip shoots down, another drifts left, two come in
//  from the right a moment later. Strips are computed deterministically
//  from time so redraws don't flicker.

import SwiftUI

struct MenuView: View {
    @Bindable var game: GameState
    /// Set true once the player picks zen or challenge. Parent view
    /// hides the menu and shows ContentView when this flips.
    @Binding var started: Bool
    @Environment(Transitioner.self) private var transitioner
    @Environment(FullVersionStore.self) private var fullVersion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var accessibilityOpen = false
    @State private var galleryOpen = false
    @State private var campaignOpen = false
    @State private var leaderboardOpen = false
    @State private var statsOpen = false
    @State private var fullVersionOpen = false
    @State private var fullVersionFocus: FullVersionFeature?
    /// True when the player has tapped "challenge" with a saved run
    /// on disk and the inline "resume?" prompt is showing. Collapses
    /// back to false when the player picks yes, no, or taps elsewhere.
    @State private var challengeResumeOpen = false
    /// Random hue anchor chosen on first appear — lets the wave field
    /// look different across cold launches without per-frame jitter.
    @State private var hueSeed: Double = Double.random(in: 0..<360)
    /// Ripples pushed in by taps on the menu background. Consumed by
    /// ContinuousGridMenuField; it prunes expired entries internally.
    @State private var ripples: [GridRipple] = []
    /// Traveling gradients live beside touch ripples so changing the
    /// interaction state never recreates and clears the existing lines.
    @State private var flares: [GridFlare] = []
    /// Position of the most recently spawned ripple during an active
    /// drag. Used as the reference point for a distance threshold —
    /// we only drop a new ripple once the finger has moved far
    /// enough from the last one to bound rendering work while still
    /// producing a connected fluid trail.
    @State private var lastRipplePoint: CGPoint? = nil
    /// 0..1 scalar tracking how deep the player is into continuous
    /// fluid interaction. Fades the menu text out as it rises; reaching
    /// the fully revealed background earns the interaction achievement.
    @State private var chill: Double = 0
    /// Timestamp of the previous drag tick. The chill ramp advances by
    /// the gap between ticks instead of by a polling task: a dragging
    /// finger already delivers events at display rate, and a resting
    /// one delivers none — which is exactly when chill should stop
    /// rising. Nil between drags.
    @State private var lastChillTick: Date? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if game.menuBackdropEnabled && !shouldReduceMotion && !isPresentingDestination {
                // Backdrop starts at 50% opacity and ramps up with the
                // chill ramp — so as the menu text fades out (driven
                // by the same `chill` variable), the backdrop
                // brightens in sync and hits full 100% the moment the
                // text has completely disappeared.
                backdrop
                    .opacity(0.5 + 0.5 * chill)
                    .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.25),
                               value: chill)
                    .ignoresSafeArea()
            }

            // Two tiers, separated by space rather than by headings:
            // the four ways to play, then the four places to go. Before
            // this every destination was the same size, so "stats" shouted
            // as loudly as "campaign" and the on-ramp was invisible.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .trailing, spacing: Kroma.Space.xl) {
                    Text(Strings.Menu.title)
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .tracking(-1)
                        .lineLimit(1)
                        // Scale the wordmark down on narrower devices
                        // (iPhone SE / mini etc.) so it never wraps to
                        // a second line. 0.6 gives plenty of headroom
                        // while keeping the letterforms readable.
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .trailing, spacing: Kroma.Space.xs) {
                        if game.hasInProgressSession && game.mode != .challenge {
                            primaryRow("resume",
                                       detail: resumeDetail,
                                       locked: resumeRequiresFullVersion) {
                                requireFullVersion(if: resumeRequiresFullVersion,
                                                   focus: resumeFullVersionFocus) {
                                    transitioner.fade {
                                        if game.resumeInProgressSession() { started = true }
                                    }
                                }
                            }
                        }
                        // Campaign sits first: it's the on-ramp, and a new
                        // player should meet it before the endless modes.
                        primaryRow(Strings.Menu.campaign,
                                   detail: campaignProgressDetail) {
                            campaignOpen = true
                        }
                        // Daily stays tappable once solved so the player can
                        // show a friend the board; the countdown replaces the
                        // call to action, and the dimming says "already done"
                        // without a "(completed)" suffix to read.
                        if game.isDailyCompletedToday {
                            dailyCompletedRow
                        } else {
                            primaryRow(Strings.Menu.todaysPuzzle,
                                       detail: dailyStreakDetail) {
                                pick(mode: .daily)
                            }
                        }
                        primaryRow(Strings.Menu.zen,
                                   detail: zenTrialAvailable ? "one puzzle free" : nil,
                                   locked: zenLocked) {
                            requireFullVersion(if: zenLocked, focus: .zen) {
                                pick(mode: .zen, asTrial: zenTrialAvailable)
                            }
                        }
                        primaryRow(Strings.Menu.challenge,
                                   detail: challengeTrialAvailable ? "one puzzle free" : nil,
                                   locked: challengeLocked) {
                            requireFullVersion(if: challengeLocked, focus: .challenge) {
                                // A saved run is the only thing that makes this
                                // ambiguous, so that's the only time we ask.
                                if game.hasSavedChallengeRun {
                                    challengeResumeOpen = true
                                } else {
                                    pick(mode: .challenge)
                                }
                            }
                        }
                    }

                    VStack(alignment: .trailing, spacing: Kroma.Space.xs) {
                        secondaryRow(Strings.Menu.gallery) {
                            galleryOpen = true
                        }
                        secondaryRow(Strings.Menu.stats) {
                            statsOpen = true
                            GameCenter.shared.reportAchievement(
                                GameCenter.Achievement.openedStats
                            )
                        }
                        secondaryRow(Strings.Menu.leaderboard) {
                            leaderboardOpen = true
                        }
                        secondaryRow(Strings.Menu.settings) {
                            accessibilityOpen = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, Kroma.Space.xxl)
                .padding(.vertical, Kroma.Space.xxl)
            }
            // The list is short at default sizes and the scroll view never
            // shows; at AX5 it is what keeps the last row reachable instead
            // of pushing it off the bottom of the screen.
            .scrollBounceBehavior(.basedOnSize)
            .opacity(1.0 - chill)
            .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.25),
                       value: chill)
        }
        // The menu content fills the screen above the visual field. Owning
        // the simultaneous gesture here makes background manipulation
        // reliable without stealing taps or scrolling from the controls.
        .contentShape(Rectangle())
        .simultaneousGesture(fluidInteractionGesture)
        .onDisappear {
            GlassyAudio.shared.stopHum()
        }
        .sheet(isPresented: $accessibilityOpen, onDismiss: {
            // Persist + regen-if-changed. Without this, settings
            // adjusted from the main menu live only in memory and
            // revert on next launch.
            game.applyAccessibilityIfChanged()
        }) {
            AccessibilitySheet(game: game)
        }
        .sheet(isPresented: $galleryOpen) {
            GalleryView(game: game, started: $started)
        }
        .sheet(isPresented: $campaignOpen) {
            CampaignView(game: game, started: $started)
        }
        .sheet(isPresented: $leaderboardOpen) {
            LeaderboardView(leaderboardID: GameCenter.dailyTimeLeaderboardID)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $statsOpen) {
            StatsView()
        }
        .sheet(isPresented: $fullVersionOpen) {
            FullVersionView(focus: fullVersionFocus)
        }
        // A suspended run is the only thing that makes "challenge"
        // ambiguous, so it's the only time we ask. This replaced an
        // inline "resume? yes no" strip that slid in beside the row and
        // shoved the whole menu sideways: the native dialog gets real
        // touch targets, real VoiceOver, and verbs instead of yes/no.
        .confirmationDialog("you have a challenge run in progress",
                            isPresented: $challengeResumeOpen,
                            titleVisibility: .visible) {
            Button("resume run") {
                transitioner.fade {
                    game.resumeChallengeRun(asTrial: challengeTrialAvailable)
                    started = true
                }
            }
            Button("start over", role: .destructive) {
                pick(mode: .challenge)
            }
            Button("cancel", role: .cancel) {}
        }
        .onAppear {
            GlassyAudio.shared.startMusicIfNeeded()
            GlassyAudio.shared.startHum()
            // One-shot hop from the in-game "← Gallery" hamburger
            // row: it sets `started=false` and this flag, then MenuView
            // auto-opens its existing Gallery sheet so the user lands
            // back where they started instead of on the main menu.
            if game.openGalleryOnMenuAppear {
                game.openGalleryOnMenuAppear = false
                galleryOpen = true
            }
            // Same one-shot hop for the campaign, so leaving a campaign
            // level lands back on the level list.
            if game.openCampaignOnMenuAppear {
                game.openCampaignOnMenuAppear = false
                campaignOpen = true
            }
        }
    }

    private var fluidInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard game.menuBackdropEnabled,
                      game.menuStyle == .continuousGrid,
                      !shouldReduceMotion,
                      !isPresentingDestination else { return }

                let now = Date()
                let loc = value.location
                let minDistance: CGFloat = 18
                let tooClose: Bool = {
                    guard let last = lastRipplePoint else { return false }
                    let dx = loc.x - last.x
                    let dy = loc.y - last.y
                    return dx * dx + dy * dy < minDistance * minDistance
                }()

                if !tooClose {
                    lastRipplePoint = loc
                    // Short, overlapping wakes feel continuous under the
                    // finger but stay bounded for the full-grid renderer.
                    if ripples.count >= 12 {
                        ripples.removeFirst(ripples.count - 11)
                    }
                    ripples.append(GridRipple(
                        origin: loc,
                        speed: 4.5,
                        spawnEpoch: now.timeIntervalSinceReferenceDate,
                        lifeSec: 2.2,
                        strength: 0.85
                    ))
                    GlassyAudio.shared.boostHum()
                }

                let gap = lastChillTick.map { now.timeIntervalSince($0) } ?? 0
                lastChillTick = now
                if gap > 0, gap < 0.5, chill < 1 {
                    let nextChill = min(1.0, chill + gap / 6.0)
                    chill = nextChill
                    if nextChill >= 1.0 {
                        GameCenter.shared.reportAchievement(
                            GameCenter.Achievement.chillMaxed
                        )
                    }
                }
            }
            .onEnded { value in
                lastRipplePoint = nil
                lastChillTick = nil
                let dist = hypot(value.translation.width, value.translation.height)
                if dist < 5 {
                    withAnimation(shouldReduceMotion ? nil : .easeOut(duration: 0.9)) {
                        chill = 0
                    }
                }
            }
    }

    /// Variant of the daily row shown once the player has solved
    /// today's puzzle. The label stays put and a live "next in Xh Ym"
    /// countdown toward the next UTC midnight leads it; taps still drop
    /// into the completed board so players can show a friend the solve.
    @ViewBuilder
    private var dailyCompletedRow: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let secs = Daily.secondsUntilNext(now: ctx.date)
            primaryRow(
                Strings.Menu.todaysPuzzle,
                detail: dailyCompletedDetail(countdown: formatCountdown(secs)),
                dimmed: true,
                // Dimming alone would encode "solved" in contrast, which
                // VoiceOver and Differentiate Without Color can't see.
                accessibilityValue: "solved, next in \(formatCountdown(secs))"
            ) {
                pick(mode: .daily)
            }
        }
    }

    /// Render a remaining-seconds value as "Xh Ym" for longer
    /// intervals or "Xm" for the final hour. Seconds precision
    /// isn't shown — the TimelineView refreshes every 30 s anyway.
    private func formatCountdown(_ secs: Int) -> String {
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(secs)s"
    }

    private var dailyStreakDetail: String? {
        let count = DailyHistoryStore.streakSummary().current
        guard count > 0 else { return nil }
        return "\(count)-day streak"
    }

    private func dailyCompletedDetail(countdown: String) -> String {
        let count = DailyHistoryStore.streakSummary().current
        guard count > 0 else { return "next in \(countdown)" }
        return "\(count)-day streak · next in \(countdown)"
    }

    /// Main-menu backdrop. Branches on game.menuStyle — palette
    /// strips (original) or the tight continuous-grid field that
    /// supports axis flares + tap ripples.
    @ViewBuilder
    private var backdrop: some View {
        switch game.menuStyle {
        case .paletteStrips:
            GeometryReader { geo in
                ZStack {
                    PaletteStripField(hueSeed: hueSeed + 217, size: geo.size,
                                       swatchPx: 20, alphaScale: 0.28,
                                       speedScale: 0.68, fps: game.menuFps)
                    PaletteStripField(hueSeed: hueSeed + 83, size: geo.size,
                                       swatchPx: 28, alphaScale: 0.42,
                                       speedScale: 1.25, fps: game.menuFps)
                    PaletteStripField(hueSeed: hueSeed, size: geo.size,
                                       swatchPx: 38, alphaScale: 0.60,
                                       speedScale: 1.45, fps: game.menuFps)
                }
            }
        case .continuousGrid:
            ContinuousGridMenuField(
                hueSeed: hueSeed,
                fps: game.menuFps,
                ripples: $ripples,
                flares: $flares
            )
        }
    }

    /// Progress hint beside the campaign row — absent until the player
    /// has actually cleared something, so a new install shows a clean
    /// "campaign" with nothing to decode.
    private var campaignProgressDetail: String? {
        let done = CampaignStore.clearedCount
        guard done > 0 else { return nil }
        return "\(done)/\(CampaignCatalog.count)"
    }

    private var resumeDetail: String {
        if let index = game.campaignIndex,
           let chapter = CampaignCatalog.chapter(containing: index),
           let local = CampaignStore.localNumber(for: index) {
            return "\(chapter.title.lowercased()) \(local)"
        }
        if game.cameFromGallery { return Strings.Menu.gallery }
        switch game.mode {
        case .daily: return "today"
        case .challenge: return "challenge"
        case .zen: return "zen"
        }
    }

    /// Honor both the system preference and Kromatika's in-app toggle.
    /// The animated backdrop is decorative, so the cleanest reduced-
    /// motion treatment is to omit it rather than leave a field that is
    /// frozen at an arbitrary frame.
    private var shouldReduceMotion: Bool {
        systemReduceMotion || game.reduceMotion
    }

    /// A presented sheet completely covers the menu. Removing the
    /// decorative backdrop while it is covered stops its display link,
    /// Canvas work, and audio-triggered visual bookkeeping until the
    /// player returns.
    private var isPresentingDestination: Bool {
        accessibilityOpen || galleryOpen || campaignOpen || leaderboardOpen || statsOpen
            || fullVersionOpen
    }

    private var zenTrialAvailable: Bool {
        !fullVersion.isUnlocked && fullVersion.canTry(.zen)
    }

    private var challengeTrialAvailable: Bool {
        !fullVersion.isUnlocked && fullVersion.canTry(.challenge)
    }

    private var zenLocked: Bool { !fullVersion.isUnlocked && !zenTrialAvailable }
    private var challengeLocked: Bool { !fullVersion.isUnlocked && !challengeTrialAvailable }

    private func pick(mode: GameMode, asTrial: Bool = false) {
        lastChillTick = nil
        withAnimation(shouldReduceMotion ? nil : .easeOut(duration: 0.9)) { chill = 0 }
        transitioner.fade {
            // `enterMode` always refreshes state — challenge always
            // starts at level 1 regardless of whether the player was
            // previously in it; zen restores the persisted level.
            game.enterMode(mode, asTrial: asTrial)
            started = true
        }
    }

    private func requireFullVersion(focus: FullVersionFeature,
                                    _ action: () -> Void) {
        requireFullVersion(if: true, focus: focus, action)
    }

    private func requireFullVersion(if required: Bool,
                                    focus: FullVersionFeature,
                                    _ action: () -> Void) {
        if !required || fullVersion.isUnlocked {
            action()
        } else {
            fullVersionFocus = focus
            fullVersionOpen = true
        }
    }

    private var resumeRequiresFullVersion: Bool {
        FullVersionAccess.sessionRequiresPurchase(
            campaignIndex: game.campaignIndex,
            mode: game.mode,
            isCustomPuzzle: game.isCustomPuzzle,
            isTrialSession: game.isTrialSession
        )
    }

    private var resumeFullVersionFocus: FullVersionFeature {
        if game.campaignIndex != nil { return .campaign }
        switch game.mode {
        case .zen:       return .zen
        case .challenge: return .challenge
        case .daily:     return .campaign
        }
    }

    /// A way to play. Sized to be read first.
    @ViewBuilder
    private func primaryRow(_ label: String,
                            detail: String? = nil,
                            dimmed: Bool = false,
                            locked: Bool = false,
                            accessibilityValue: String? = nil,
                            action: @escaping () -> Void) -> some View {
        menuRow(label,
                detail: detail,
                font: Kroma.font(.title, .semibold),
                // 0.34 on black is ~2.9:1 — below WCAG AA's 4.5:1 and
                // below even the 3:1 large-text allowance, on a row a
                // player lands on every day once they've solved the
                // daily. "Already done" is still carried by the detail
                // text ("next in 5h 20m"); the label doesn't also need
                // to be near-invisible to say it.
                opacity: dimmed ? 0.50 : 0.78,
                locked: locked,
                accessibilityValue: locked ? "requires full version" : accessibilityValue,
                action: action)
    }

    /// A place to go rather than a way to play. Same voice, quieter.
    @ViewBuilder
    private func secondaryRow(_ label: String,
                              locked: Bool = false,
                              action: @escaping () -> Void) -> some View {
        menuRow(label,
                detail: nil,
                font: Kroma.font(.headline, .medium),
                opacity: 0.52,
                locked: locked,
                accessibilityValue: locked ? "requires full version" : nil,
                action: action)
    }

    /// Shared row body. The optional detail leads the label so every
    /// row's right edge stays on one axis no matter how long the
    /// countdown or progress fraction gets.
    @ViewBuilder
    private func menuRow(_ label: String,
                         detail: String?,
                         font: Font,
                         opacity: Double,
                         locked: Bool,
                         accessibilityValue: String?,
                         action: @escaping () -> Void) -> some View {
        Button {
            // Menu button press counts as a reset for chill —
            // brings the menu text back to full opacity and drops
            // ripple lifetimes to baseline.
            lastChillTick = nil
            withAnimation(shouldReduceMotion ? nil : .easeOut(duration: 0.9)) { chill = 0 }
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Kroma.Space.m) {
                if let detail {
                    Text(detail)
                        // 0.45 lands at ~4.4:1, just under AA. This is
                        // the streak / "next in" / "one puzzle free"
                        // text on every primary row, so it's worth the
                        // extra .05 to clear the bar.
                        .font(Kroma.font(.subheadline, .semibold))
                        .foregroundStyle(Color.white.opacity(0.50))
                }
                Text(label)
                    .font(font)
                    .foregroundStyle(Color.white.opacity(opacity))
                if locked {
                    Image(systemName: "lock.fill")
                        .font(Kroma.font(.caption, .bold))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .accessibilityHidden(true)
                }
            }
            .multilineTextAlignment(.trailing)
            // No fixed height: at AX5 these rows are several lines tall
            // and must be allowed to grow.
            .padding(.vertical, Kroma.Space.m)
            .frame(minHeight: Kroma.Metrics.minTarget, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.kromaControl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue ?? detail ?? "")
    }
}

// ─── Rendering ───────────────────────────────────────────────────────

private struct PaletteStripField: View {
    let hueSeed: Double
    let size: CGSize
    /// Per-layer swatch size. Smaller values push the layer visually
    /// further back (parallax illusion stacks with alphaScale +
    /// speedScale).
    let swatchPx: CGFloat
    /// Per-layer alpha multiplier. Back layers = dimmer.
    let alphaScale: Double
    /// Per-layer travel-speed multiplier. Back layers = slower, as
    /// with real-world depth cues.
    let speedScale: Double
    /// Animation frame rate — driven by the user's Accessibility
    /// setting so ProMotion devices can opt into 120 fps while
    /// slower devices can drop to 30.
    let fps: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / Double(max(15, fps)))) { timeline in
            Canvas { context, canvasSize in
                drawStrips(context: context, size: canvasSize, time: timeline.date)
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private var swatchGap: CGFloat { max(2, swatchPx * 0.1) }
    /// Average seconds between new strip spawns — smaller = busier,
    /// larger = sparser. Doubled from 1.4 → 2.8 to cut the active-
    /// palette count per layer in half (fewer drawStrip calls per
    /// frame, fewer candidate slots to iterate in the conflict-
    /// resolution pass).
    private let spawnInterval: Double = 2.8
    /// Worst-case strip lifetime — drives how far back we look when
    /// computing which strips are currently visible. 45s covers the
    /// slowest front-of-layer strips at their longest (life ≈ 30s
    /// for a 22-swatch strip at ~70pt/s across a ~2000pt total
    /// travel). Dropped from 90s to halve the number of slot
    /// candidates we iterate per frame.
    private let maxTravelSec: Double = 45.0

    private enum StripDirection { case down, up, left, right }

    private struct Strip {
        let spawnTime: Double
        let direction: StripDirection
        /// x (for vertical strips) or y (for horizontal) of the strip's
        /// long axis. Snapped to the swatch pitch so strips align.
        /// `var` because `drawStrips` may shift the axis during lane
        /// conflict resolution (see below).
        var axis: CGFloat
        let length: Int
        let hueAnchor: Double
        let lAnchor: Double
        let cAnchor: Double
        let speed: CGFloat   // pt/sec
    }

    private func drawStrips(context: GraphicsContext, size: CGSize, time: Date) {
        let t = time.timeIntervalSinceReferenceDate
        let currentSlot = Int(floor(t / spawnInterval))
        let lookback = Int(ceil(maxTravelSec / spawnInterval)) + 1
        let pitch = swatchPx + swatchGap
        // Process strips in slot order (oldest first) and SUPPRESS
        // any strip whose direction+lane is already occupied by an
        // earlier, still-active strip. A strip "claims" its lane for
        // the entirety of its life on screen; concurrent same-
        // direction strips cannot share a lane. When a would-be
        // later strip collides, it simply doesn't spawn — the lane
        // stays held by the occupant until it exits.
        var accepted: [(strip: Strip, age: Double)] = []
        for offset in (-lookback)...1 {
            let slot = currentSlot + offset
            let s = strip(forSlot: slot, size: size)
            let age = t - s.spawnTime
            guard age >= 0 else { continue }
            let primaryDim: CGFloat = (s.direction == .down || s.direction == .up)
                ? size.height : size.width
            let stripLen = CGFloat(s.length) * pitch
            let travel = CGFloat(age) * s.speed
            if travel > primaryDim + stripLen + pitch { continue }

            let axisSpan: CGFloat = (s.direction == .down || s.direction == .up)
                ? size.width : size.height
            let lanes = max(3, Int(floor(axisSpan / pitch)))
            let laneIdx = Int(((s.axis - pitch / 2) / pitch).rounded())
            let normLane = ((laneIdx % lanes) + lanes) % lanes
            // Same axis family (vertical ↔ vertical, horizontal ↔
            // horizontal) blocks regardless of travel direction. A
            // down-moving strip in column 5 blocks an up-moving strip
            // in column 5 just as much as another down-moving one —
            // they'd occupy the same visual grid slot on this layer.
            let sVertical = (s.direction == .down || s.direction == .up)
            let conflict = accepted.contains { a in
                let aVertical = (a.strip.direction == .down || a.strip.direction == .up)
                guard aVertical == sVertical else { return false }
                let aLane = Int(((a.strip.axis - pitch / 2) / pitch).rounded())
                return (((aLane % lanes) + lanes) % lanes) == normLane
            }
            if conflict { continue }
            accepted.append((strip: s, age: age))
        }
        for a in accepted {
            drawStrip(a.strip, age: a.age, context: context, canvasSize: size)
        }
    }

    /// Deterministic per-slot strip. Same slot always returns the same
    /// strip within a launch; hueSeed differs per cold launch so the
    /// menu looks fresh each time.
    private func strip(forSlot slot: Int, size: CGSize) -> Strip {
        var state = UInt64(bitPattern: Int64(slot)) &* 0x9E3779B97F4A7C15
        state ^= UInt64(bitPattern: Int64(hueSeed * 1_000)) &* 0xBF58476D1CE4E5B9
        func nextBits() -> UInt64 {
            state ^= state >> 30; state &*= 0xBF58476D1CE4E5B9
            state ^= state >> 27; state &*= 0x94D049BB133111EB
            state ^= state >> 31
            return state
        }
        func nextFloat() -> Double {
            Double(nextBits() >> 11) / Double(1 << 53)
        }
        let jitter = (nextFloat() - 0.5) * spawnInterval * 0.6
        let spawnTime = Double(slot) * spawnInterval + jitter
        let dirPick = nextFloat()
        let direction: StripDirection = {
            // Vertical slightly more common than horizontal — reads
            // as columns descending more than sidebars drifting.
            if dirPick < 0.32 { return .down }
            if dirPick < 0.60 { return .up }
            if dirPick < 0.80 { return .right }
            return .left
        }()
        let pitch = swatchPx + swatchGap
        let axisSpan: CGFloat = (direction == .down || direction == .up)
            ? size.width : size.height
        let lanes = max(3, Int(floor(axisSpan / pitch)))
        let laneIdx = Int(nextFloat() * Double(lanes))
        let axis = CGFloat(laneIdx) * pitch + pitch / 2
        let length = 12 + Int(nextFloat() * 11) // 12..22
        let hueAnchor = hueSeed + nextFloat() * 360
        let lAnchor = 0.28 + nextFloat() * 0.22   // 0.28..0.50
        let cAnchor = 0.06 + nextFloat() * 0.10   // 0.06..0.16
        let speed = (80 + CGFloat(nextFloat()) * 140) * CGFloat(speedScale) // 80..220 × layer scale — raised floor so slowest strips finish within maxTravelSec
        return Strip(spawnTime: spawnTime,
                     direction: direction,
                     axis: axis,
                     length: length,
                     hueAnchor: hueAnchor,
                     lAnchor: lAnchor,
                     cAnchor: cAnchor,
                     speed: speed)
    }

    private func drawStrip(_ s: Strip, age: Double,
                           context: GraphicsContext, canvasSize: CGSize) {
        let pitch = swatchPx + swatchGap
        let travel = CGFloat(age) * s.speed
        let primaryDim: CGFloat = (s.direction == .down || s.direction == .up)
            ? canvasSize.height : canvasSize.width
        let stripLen = CGFloat(s.length) * pitch
        // Keep drawing until the trailing swatch has fully cleared
        // the far edge — plus a small pitch margin so the fade-out
        // tail reaches zero before we stop iterating.
        if travel > primaryDim + stripLen + pitch { return }

        let radius = swatchPx * 0.26
        // Traveling alpha-orb: a conceptual "spotlight" that slides
        // along the strip from head (i=0) to tail (i=length-1) over
        // the strip's entire life on screen. The orb itself isn't
        // drawn; it only modulates a subtle brightening around the
        // swatch closest to its current position.
        let life = primaryDim + stripLen
        let lifeT = max(0, min(1, travel / life))
        let orbI = lifeT * Double(max(0, s.length - 1))
        // Tighter sigma than before so the orb reads as a clear
        // "ball" of opacity gliding along each palette, rather than
        // a vague swell. Scales with length so the lit region still
        // covers a meaningful fraction of short strips.
        let orbSigma: Double = max(2.0, Double(s.length) * 0.20)
        // Screen-position fade margin: how far inside the canvas a
        // swatch has to be before it reaches full alpha. Generous
        // (5 pitches ≈ a fifth of the screen) so every swatch's
        // entry and exit is gradual — enough runway that even a
        // bright (orb-lit) swatch doesn't pop in as it crosses the
        // edge.
        let fadeMargin: CGFloat = pitch * 5.0

        for i in 0..<s.length {
            // travelPos: distance from the spawn edge along the
            // travel direction. Leading swatch (i=0) starts at
            // -pitch/2 (just off-screen) and moves inward as travel
            // grows. Trailing swatches (larger i) sit behind by i*pitch.
            let travelPos = travel - pitch / 2 - CGFloat(i) * pitch
            // Cull 8 pitches past either edge — gives a generous
            // invisible runway so every palette spawns far off-screen
            // and retires far off-screen, with no abrupt appear /
            // disappear at the visible boundary.
            if travelPos < -pitch * 8 { continue }
            if travelPos > primaryDim + pitch * 8 { continue }

            // Screen fade via smoothstep — 0 at the spawn edge, 1
            // once fully inside, 1 through the middle, 0 again on
            // exit. Smoothstep's gentle ease-in/out means the early
            // rise is slow even when fadeMargin is large — no hard
            // linear ramp that the eye reads as a pop.
            let entryT = max(0, min(1.0, (travelPos + pitch / 2) / fadeMargin))
            let exitT  = max(0, min(1.0, ((primaryDim - travelPos) + pitch / 2) / fadeMargin))
            let entryFade = entryT * entryT * (3 - 2 * entryT)
            let exitFade  = exitT  * exitT  * (3 - 2 * exitT)
            let screenFade = entryFade * exitFade
            if screenFade < 0.01 { continue }

            // Orb modulation — the travelling "ball of opacity" that
            // swipes along each palette. Baseline 0.25 everywhere so
            // swatches far from the orb are clearly dimmer; peak
            // 1.00 at the orb's current position draws the eye to
            // the moving highlight.
            let dist = abs(Double(i) - orbI)
            let proximity = exp(-dist * dist / (2 * orbSigma * orbSigma))
            let modulation = 0.25 + 0.75 * proximity

            // Tail fade — index-based, only on the trailing end of
            // the strip. The last ~7 swatches fade progressively
            // toward zero (smoothstep ramp) so a palette "trails
            // off" into invisibility rather than ending in a hard
            // edge. Head-side fade is handled by the screen-position
            // smoothstep above, so we only apply this one-sided.
            let tailShoulder: Double = 7.0
            let endDist = Double(s.length - 1 - i)
            let tailT = min(1.0, endDist / tailShoulder)
            let tailFade = tailT * tailT * (3 - 2 * tailT)

            let alpha = 0.92 * alphaScale * screenFade * modulation * tailFade
            if alpha < 0.015 { continue }

            let center: CGPoint = {
                switch s.direction {
                case .down:  return CGPoint(x: s.axis,                   y: travelPos)
                case .up:    return CGPoint(x: s.axis,                   y: canvasSize.height - travelPos)
                case .right: return CGPoint(x: travelPos,                y: s.axis)
                case .left:  return CGPoint(x: canvasSize.width - travelPos, y: s.axis)
                }
            }()

            // Per-swatch hue walks a wide range along the strip so
            // the row reads as a real palette — visible color travel
            // end-to-end, not a near-monochrome column. Spans about
            // 40% of the color wheel so a long strip can go
            // red → orange → yellow → green (for example) over its
            // length. L and c stay at the strip's anchor — only hue
            // moves.
            let hueSpread = 150.0 * (Double(i) / Double(max(1, s.length - 1))) - 75.0
            let oklch = OKLCh(
                L: max(OK.lMin + 0.02, min(OK.lMax - 0.02, s.lAnchor)),
                c: max(OK.cMin + 0.005, min(OK.cMax - 0.01, s.cAnchor)),
                h: OK.normH(s.hueAnchor + hueSpread)
            )
            let rect = CGRect(x: center.x - swatchPx / 2,
                              y: center.y - swatchPx / 2,
                              width: swatchPx, height: swatchPx)
            let path = Path(roundedRect: rect, cornerRadius: radius)
            context.fill(path, with: .color(OK.toColor(oklch, opacity: alpha)))
        }
    }

    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
