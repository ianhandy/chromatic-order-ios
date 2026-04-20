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

    @State private var accessibilityOpen = false
    @State private var galleryOpen = false
    @State private var leaderboardOpen = false
    @State private var statsOpen = false
    /// Random hue anchor chosen on first appear — lets the wave field
    /// look different across cold launches without per-frame jitter.
    @State private var hueSeed: Double = Double.random(in: 0..<360)

    /// One tap-tone per button — each is a distinct OKLCh color so the
    /// audio mapping (hue → pentatonic degree, L → octave) picks a
    /// different pitch for each button. Colors also serve as a subtle
    /// visual accent if we ever want to surface them.
    private static let zenColor       = OKLCh(L: 0.62, c: 0.14, h: 150)
    private static let challengeColor = OKLCh(L: 0.55, c: 0.18, h: 28)
    private static let dailyColor     = OKLCh(L: 0.60, c: 0.16, h: 95)
    private static let galleryColor   = OKLCh(L: 0.58, c: 0.16, h: 290)
    private static let optionsColor   = OKLCh(L: 0.70, c: 0.08, h: 220)
    private static let leaderboardColor = OKLCh(L: 0.65, c: 0.14, h: 50)
    private static let statsColor     = OKLCh(L: 0.60, c: 0.10, h: 260)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if game.menuBackdropEnabled {
                GeometryReader { geo in
                    // Three layers of palette strips — deepest first
                    // so the frontmost composites on top. Each layer
                    // gets smaller swatches, lower alpha and slower
                    // travel, so they read as receding into the
                    // distance. Distinct hueSeed offsets keep the
                    // layers out of sync with each other. Was four
                    // layers; dropped the deepest one for menu
                    // performance.
                    ZStack {
                        PaletteStripField(hueSeed: hueSeed + 217, size: geo.size,
                                           swatchPx: 20, alphaScale: 0.48,
                                           speedScale: 0.68, fps: game.menuFps)
                        PaletteStripField(hueSeed: hueSeed + 83, size: geo.size,
                                           swatchPx: 28, alphaScale: 0.72,
                                           speedScale: 0.86, fps: game.menuFps)
                        PaletteStripField(hueSeed: hueSeed, size: geo.size,
                                           swatchPx: 38, alphaScale: 1.00,
                                           speedScale: 1.00, fps: game.menuFps)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Spacer()
                Text("kromatika")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .tracking(-1)
                    .lineLimit(1)
                    // Scale the wordmark down on narrower devices
                    // (iPhone SE / mini etc.) so it never wraps to
                    // a second line. 0.6 gives plenty of headroom
                    // while keeping the letterforms readable.
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 40)
                menuButton("zen", tone: Self.zenColor) {
                    pick(mode: .zen)
                }
                menuButton("challenge", tone: Self.challengeColor) {
                    pick(mode: .challenge)
                }
                menuButton("today's puzzle", tone: Self.dailyColor) {
                    pick(mode: .daily)
                }
                menuButton("gallery", tone: Self.galleryColor) {
                    galleryOpen = true
                }
                menuButton("options", tone: Self.optionsColor) {
                    accessibilityOpen = true
                }
                menuButton("leaderboard", tone: Self.leaderboardColor) {
                    leaderboardOpen = true
                }
                menuButton("stats", tone: Self.statsColor) {
                    statsOpen = true
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
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
        .sheet(isPresented: $leaderboardOpen) {
            LeaderboardView(leaderboardID: GameCenter.challengeLeaderboardID)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $statsOpen) {
            StatsView()
        }
        .onAppear {
            GlassyAudio.shared.startMusicIfNeeded()
        }
    }

    private func pick(mode: GameMode) {
        transitioner.fade {
            // `enterMode` always refreshes state — challenge always
            // starts at level 1 regardless of whether the player was
            // previously in it; zen restores the persisted level.
            game.enterMode(mode)
            started = true
        }
    }

    @ViewBuilder
    private func menuButton(_ label: String, tone: OKLCh,
                             action: @escaping () -> Void) -> some View {
        Button {
            // Random F# Phrygian bloom — each press picks its own
            // voicing (most often a single note, occasionally a
            // two- or three-note chord), so the buttons have a
            // musical feel without being locked to fixed pitches.
            GlassyAudio.shared.playBloom()
            action()
        } label: {
            Text(label)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.70))
                .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
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
