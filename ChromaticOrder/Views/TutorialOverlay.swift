//  First-run tutorials surfaced as small non-blocking tooltips. A
//  short capsule pinned near the top of the screen; the player can
//  keep playing while the tooltip is up and dismiss it with the X.
//  Shown once per mode via TutorialStore.
//
//  The daily show-answers prompt is NOT a tutorial — it's a binary
//  decision dialog, so it stays full-screen (DailyShowAnswersPrompt
//  below).

import SwiftUI

struct TutorialTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .allowsHitTesting(false)
    }
}

// ─── Tutorial pointer-line anchors + arrow ──────────────────────────

/// Shared anchor bag so separate views (the level chip, the zen
/// tooltip) can publish their on-screen frames and an overlay layer
/// can resolve both in one pass to draw a line between them.
struct TutorialAnchorsKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Straight line from `from` to `to` with a small arrowhead at the
/// `to` end pointing in the line's direction. Thin stroke — this is
/// meant to read as a guide-line, not a bold UI element.
struct TutorialArrowShape: Shape {
    var from: CGPoint
    var to: CGPoint
    /// Length of each arrowhead "wing" in points.
    let headLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let leftAngle = angle + .pi - .pi / 7
        let rightAngle = angle + .pi + .pi / 7
        let left = CGPoint(
            x: to.x + cos(leftAngle) * headLength,
            y: to.y + sin(leftAngle) * headLength
        )
        let right = CGPoint(
            x: to.x + cos(rightAngle) * headLength,
            y: to.y + sin(rightAngle) * headLength
        )
        path.move(to: left)
        path.addLine(to: to)
        path.addLine(to: right)
        return path
    }
}

// ─── Balloon tutorials ──────────────────────────────────────────────

/// Exit choreography the balloon plays before unmounting.
///   alive    — idle sway, accepts taps / drag deflection
///   floating — released by first tap, drifts up slowly, still tappable
///   released — floats up and off-screen (auto-dismiss), then calls `onFinished`
///   popped   — quick scale-up + fade, then calls `onFinished`
enum TutorialBalloonExit { case alive, floating, released, popped }

/// Cartoon-balloon-shaped tutorial bubble. Replaces the flat
/// TutorialTooltip when reduce-motion is off. Physics are deliberately
/// lightweight — sway + float-away + finger-deflect — the balloon is
/// not a full particle simulation, just enough to read as "floating
/// thing with some whimsy." Reduce-motion users see the flat tooltip.
struct TutorialBalloon: View {
    let text: String
    let tint: Color
    /// `.alive` while the tutorial is live; flips to `.released` on
    /// normal dismissal (menu open, first-placement, level change) or
    /// `.popped` when the player taps the balloon.
    let exit: TutorialBalloonExit
    /// Called when the balloon's exit animation completes so the
    /// parent can unmount it + clear the flag.
    let onFinished: () -> Void
    /// Fires the moment the balloon is tapped (before the pop animation
    /// plays out). Parent uses it to mark the tutorial seen so the pop
    /// is treated as a real dismiss.
    let onTap: () -> Void
    /// Anchor-preference key under which to publish the knot's
    /// on-screen position. The parent overlay reads this together
    /// with the level chip anchor to draw the connecting string +
    /// arrow so it tracks the balloon's live (swayed/floated) pose.
    let knotAnchorKey: String
    /// Render a small ↖ glyph in the balloon's upper-left corner so
    /// the player has an in-balloon hint pointing at whatever the
    /// tutorial is calling out (e.g. the level chip for zenIntro).
    var cornerArrow: Bool = false

    @State private var appearAt: Date? = nil
    @State private var exitStartedAt: Date? = nil

    private static let balloonSize = CGSize(width: 120, height: 150)
    private static let knotHeight: CGFloat = 10
    /// Length of the dangling string below the knot.
    private static let stringLength: CGFloat = 50

    var body: some View {
        // TimelineView drives the per-frame sway + float-away + deflect
        // decay math. Body of the closure just reads the latest pose
        // from `computePose` so there's no control flow inside the
        // ViewBuilder closure.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let pose = computePose(at: ctx.date)
            balloonVisual
                .offset(x: pose.offset.width, y: pose.offset.height)
                .rotationEffect(.degrees(pose.angle))
                .scaleEffect(pose.scale)
                .opacity(pose.opacity)
                .animation(nil, value: ctx.date)
        }
        .frame(width: Self.balloonSize.width,
               height: Self.balloonSize.height + Self.knotHeight + Self.stringLength + 12)
        .contentShape(Rectangle())
        // Only hit-test while alive or floating — after release/pop
        // the balloon must not eat the player's taps.
        .allowsHitTesting(exit == .alive || exit == .floating)
        .onTapGesture {
            if exit == .alive || exit == .floating {
                onTap()
            }
        }
    }

    @ViewBuilder
    private var balloonVisual: some View {
        let bodyH = Self.balloonSize.height + Self.knotHeight
        ZStack {
            // Balloon body
            BalloonBodyShape()
                .fill(tint.opacity(0.55))
                .overlay(
                    BalloonBodyShape()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
                .frame(width: Self.balloonSize.width, height: bodyH)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            // Specular highlight — small bright ellipse in the
            // upper-left quadrant reads as inflated rubber.
            Ellipse()
                .fill(Color.white.opacity(0.20))
                .frame(width: Self.balloonSize.width * 0.28,
                       height: Self.balloonSize.height * 0.20)
                .offset(x: -Self.balloonSize.width * 0.15,
                        y: -Self.balloonSize.height * 0.25)
                .allowsHitTesting(false)
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .frame(width: Self.balloonSize.width - 8,
                       height: Self.balloonSize.height * 0.65,
                       alignment: .center)
                .offset(y: -Self.balloonSize.height * 0.10
                         - Self.stringLength / 2)
            // Up-left corner pointer — only rendered when the parent
            // wires it in (e.g. the zen-intro tutorial). Sits inside
            // the balloon's upper-left lobe so it reads as part of
            // the bubble surface rather than another floating chrome
            // element.
            if cornerArrow {
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.30), radius: 1.5, y: 1)
                    .offset(x: -Self.balloonSize.width * 0.25,
                            y: -Self.balloonSize.height * 0.32)
                    .allowsHitTesting(false)
            }
            // Dangling string below the knot
            BalloonDanglingString(swayPhase: swayPhase)
                .stroke(Color.white.opacity(0.70),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 30, height: Self.stringLength)
                .offset(y: bodyH / 2 + Self.stringLength / 2)
            // Knot position anchor
            Color.clear
                .frame(width: 1, height: 1)
                .offset(y: bodyH / 2)
                .transformAnchorPreference(
                    key: TutorialAnchorsKey.self,
                    value: .bounds
                ) { [knotAnchorKey] value, anchor in
                    value[knotAnchorKey] = anchor
                }
            // Balloon center anchor — for pop-particle burst
            Color.clear
                .frame(width: 1, height: 1)
                .offset(y: -Self.stringLength / 2)
                .transformAnchorPreference(
                    key: TutorialAnchorsKey.self,
                    value: .bounds
                ) { value, anchor in
                    value["balloonCenter"] = anchor
                }
        }
    }

    /// Current sway phase based on age — used by the dangling string
    /// to wave in sync with the balloon body.
    private var swayPhase: Double {
        guard let birth = appearAt else { return 0 }
        let alive = exit == .alive || exit == .floating
        guard alive else { return 0 }
        return Date().timeIntervalSince(birth)
    }

    /// One-tick snapshot of the balloon's current visual pose —
    /// composition of idle sway and exit animation (release / pop).
    private struct BalloonPose {
        var offset: CGSize
        var angle: Double
        var scale: CGFloat
        var opacity: Double
    }

    private func computePose(at t: Date) -> BalloonPose {
        if appearAt == nil {
            DispatchQueue.main.async {
                if appearAt == nil { appearAt = t }
            }
        }
        let birth = appearAt ?? t
        let age = t.timeIntervalSince(birth)
        let isStationary = exit == .alive || exit == .floating
        // Sway — bigger amplitude + slower frequency reads as a
        // lighter, floatier balloon instead of a tethered ornament.
        // Floating balloons sway at reduced amplitude (untethered).
        let swayAmp: Double = exit == .alive ? 1.0 : (exit == .floating ? 0.6 : 0)
        let swayX = swayAmp * sin(age * 0.65) * 9.0
        let swayY = swayAmp * cos(age * 0.45) * 6.5
        let swayAngle = swayAmp * sin(age * 0.40) * 3.5
        // Exit animations.
        var floatX: CGFloat = 0
        var floatY: CGFloat = 0
        var floatAngle: Double = 0
        var popScale: CGFloat = 1
        var exitOpacity: Double = 1
        if !isStationary || exit == .floating {
            if exitStartedAt == nil {
                DispatchQueue.main.async {
                    if exitStartedAt == nil { exitStartedAt = t }
                }
            }
            let started = exitStartedAt ?? t
            let dt = t.timeIntervalSince(started)
            switch exit {
            case .floating:
                // Gentle upward drift — slow enough to tap again
                let up = -60 * dt
                let drift = sin(dt * 0.9 + age) * 18
                floatX = CGFloat(drift)
                floatY = CGFloat(up)
                floatAngle = sin(dt * 1.2) * 4
                exitOpacity = max(0, 1 - dt / 4.0)
                if dt > 4.5 {
                    DispatchQueue.main.async { onFinished() }
                }
            case .released:
                let up = -180 * dt - 60 * dt * dt
                let drift = sin(dt * 1.3 + age) * 28
                floatX = CGFloat(drift)
                floatY = CGFloat(up)
                floatAngle = sin(dt * 1.8) * 6
                exitOpacity = max(0, 1 - dt / 2.8)
                if dt > 3.0 {
                    DispatchQueue.main.async { onFinished() }
                }
            case .popped:
                // Snappy pop — body scales up briefly and the alpha
                // collapses faster than before so the particles take
                // over as the primary "something happened" cue.
                popScale = 1 + CGFloat(dt) * 5.5
                exitOpacity = max(0, 1 - dt / 0.09)
                if dt > 0.11 {
                    DispatchQueue.main.async { onFinished() }
                }
            case .alive:
                break
            }
        }
        return BalloonPose(
            offset: CGSize(
                width: swayX + Double(floatX),
                height: swayY + Double(floatY)
            ),
            angle: swayAngle + floatAngle,
            scale: popScale,
            opacity: exitOpacity
        )
    }
}

/// Classic balloon silhouette — round dome at the top, gentle taper
/// to a narrow neck, and a small tied-knot nub at the bottom. Drawn
/// as a single continuous Path so fill + stroke line up without seams.
struct BalloonBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let knotH: CGFloat = 8
        let bodyH = rect.height - knotH
        let w = rect.width
        let cx = rect.midX
        let topY = rect.minY
        // Widest point ~46% down gives plenty of vertical room for
        // the dome to arc into a full, round shape.
        let wideY = topY + bodyH * 0.46
        let bottomY = topY + bodyH
        let halfW = w * 0.50
        let neckHalfW = w * 0.055

        var p = Path()
        p.move(to: CGPoint(x: cx, y: topY))

        // ── Right side ──────────────────────────────────────────

        // Top-right dome — c1 pulls above the apex so the curve
        // bulges upward into a full round arc.
        p.addCurve(
            to: CGPoint(x: cx + halfW, y: wideY),
            control1: CGPoint(x: cx + halfW * 0.56, y: topY - bodyH * 0.04),
            control2: CGPoint(x: cx + halfW * 1.10, y: topY + bodyH * 0.12)
        )
        // Bottom-right taper to neck
        p.addCurve(
            to: CGPoint(x: cx + neckHalfW, y: bottomY),
            control1: CGPoint(x: cx + halfW * 0.96, y: wideY + bodyH * 0.34),
            control2: CGPoint(x: cx + neckHalfW * 2.2, y: bottomY - bodyH * 0.06)
        )

        // ── Knot nub (integrated into the path) ────────────────

        let knotBottomY = bottomY + knotH
        // Right side of knot — small curve bulging right then down
        p.addCurve(
            to: CGPoint(x: cx, y: knotBottomY),
            control1: CGPoint(x: cx + neckHalfW + 3, y: bottomY + knotH * 0.15),
            control2: CGPoint(x: cx + 2, y: knotBottomY)
        )
        // Left side of knot — mirror curve back up
        p.addCurve(
            to: CGPoint(x: cx - neckHalfW, y: bottomY),
            control1: CGPoint(x: cx - 2, y: knotBottomY),
            control2: CGPoint(x: cx - neckHalfW - 3, y: bottomY + knotH * 0.15)
        )

        // ── Left side (mirror) ──────────────────────────────────

        // Bottom-left taper
        p.addCurve(
            to: CGPoint(x: cx - halfW, y: wideY),
            control1: CGPoint(x: cx - neckHalfW * 2.2, y: bottomY - bodyH * 0.06),
            control2: CGPoint(x: cx - halfW * 0.96, y: wideY + bodyH * 0.34)
        )
        // Top-left dome (mirror)
        p.addCurve(
            to: CGPoint(x: cx, y: topY),
            control1: CGPoint(x: cx - halfW * 1.10, y: topY + bodyH * 0.12),
            control2: CGPoint(x: cx - halfW * 0.56, y: topY - bodyH * 0.04)
        )
        p.closeSubpath()
        return p
    }
}

/// Dangling string below the balloon's knot. Sways gently in sync
/// with the balloon body via a time-varying Bezier control point.
struct BalloonDanglingString: Shape {
    var swayPhase: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let swayOffset = sin(swayPhase * 0.65) * 8.0
        let ctrl = CGPoint(x: rect.midX + swayOffset,
                           y: rect.midY + rect.height * 0.15)
        p.move(to: top)
        p.addQuadCurve(to: bottom, control: ctrl)
        return p
    }
}

/// Curved string + tiny arrowhead connecting a balloon's knot to a
/// target (typically the level chip). Drawn in the overlay layer so
/// both endpoints come from post-transform anchor frames and the
/// string tracks the live balloon pose. The curve bends via a
/// quadratic control point offset below the segment midpoint so it
/// reads as slack string rather than a ruler.
struct BalloonStringToTargetShape: Shape {
    var knot: CGPoint
    var target: CGPoint
    /// Arrowhead "wing" length in points — matches the old
    /// TutorialArrowShape sizing.
    var headLength: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: knot)
        let mid = CGPoint(x: (knot.x + target.x) / 2,
                          y: (knot.y + target.y) / 2)
        let ctrl = CGPoint(x: mid.x, y: mid.y + 22)
        p.addQuadCurve(to: target, control: ctrl)
        // Tangent at the target end drives arrowhead orientation.
        // Derivative of a quadratic Bezier at t=1 is 2*(P2 - P1), so
        // the incoming direction is (target - ctrl).
        let angle = atan2(target.y - ctrl.y, target.x - ctrl.x)
        let leftAngle = angle + .pi - .pi / 7
        let rightAngle = angle + .pi + .pi / 7
        let left = CGPoint(
            x: target.x + cos(leftAngle) * headLength,
            y: target.y + sin(leftAngle) * headLength
        )
        let right = CGPoint(
            x: target.x + cos(rightAngle) * headLength,
            y: target.y + sin(rightAngle) * headLength
        )
        p.move(to: left)
        p.addLine(to: target)
        p.addLine(to: right)
        return p
    }

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(knot.x, knot.y),
                AnimatablePair(target.x, target.y)
            )
        }
        set {
            knot = CGPoint(x: newValue.first.first, y: newValue.first.second)
            target = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }
}

// ─── Pop-particle burst ─────────────────────────────────────────────

/// Single physical fragment thrown outward when a balloon pops.
/// Kept as a value type so the particle array can be swapped wholesale
/// in one mutation per frame instead of poking individual particles.
struct PopParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var angle: Double
    var angularVelocity: Double
    var size: CGFloat
    var color: Color
    let spawnDate: Date
}

/// Short-lived confetti explosion. Spawns 18 fragments at `origin`,
/// scatters them with randomized outward velocities, and lets gravity
/// drag them to the bottom of the container. The burst unmounts
/// itself via `onFinished` once every fragment has fallen off-screen
/// or the max life elapses.
struct BalloonPopParticles: View {
    let origin: CGPoint
    let tint: Color
    let containerHeight: CGFloat
    let onFinished: () -> Void

    @State private var particles: [PopParticle] = []
    @State private var started: Bool = false
    @State private var lastTick: Date? = nil

    private static let spawnCount = 18
    private static let maxLife: TimeInterval = 2.2
    /// Downward acceleration in pt/s². Tuned by eye — slower than real
    /// gravity so the arc feels floaty / rubbery rather than like lead.
    private static let gravity: Double = 900

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            particleBodies(at: ctx.date)
                .onChange(of: ctx.date) { _, newDate in
                    advance(to: newDate)
                }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func particleBodies(at _: Date) -> some View {
        ZStack {
            ForEach(particles) { p in
                RoundedRectangle(cornerRadius: p.size * 0.35,
                                 style: .continuous)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 0.55)
                    .rotationEffect(.degrees(p.angle))
                    .position(p.position)
                    .opacity(opacity(for: p))
            }
        }
    }

    /// Physics integration — pulled out of the TimelineView builder
    /// so there's no control-flow inside the ViewBuilder closure.
    /// Runs once per tick; splits first-tick spawn from steady-state
    /// motion so particles only get initialized once.
    private func advance(to now: Date) {
        if !started {
            started = true
            lastTick = now
            particles = spawnParticles()
            return
        }
        let dt = max(0, min(1.0 / 30.0, now.timeIntervalSince(lastTick ?? now)))
        lastTick = now
        var live: [PopParticle] = []
        live.reserveCapacity(particles.count)
        for var p in particles {
            p.velocity.dy += Self.gravity * dt
            p.position.x += p.velocity.dx * dt
            p.position.y += p.velocity.dy * dt
            p.angle += p.angularVelocity * dt
            if p.position.y < containerHeight + 40,
               now.timeIntervalSince(p.spawnDate) < Self.maxLife {
                live.append(p)
            }
        }
        particles = live
        if particles.isEmpty && started {
            onFinished()
        }
    }

    private func spawnParticles() -> [PopParticle] {
        let spawn = Date()
        return (0..<Self.spawnCount).map { _ in
            // Bias velocity slightly upward + outward so the initial
            // burst reads as a "pop" rather than just a spill.
            let angleRad = Double.random(in: -.pi...0) - .pi / 8
            let speed = Double.random(in: 260...520)
            let vx = cos(angleRad) * speed
            let vy = sin(angleRad) * speed
            return PopParticle(
                position: origin,
                velocity: CGVector(dx: vx, dy: vy),
                angle: Double.random(in: -45...45),
                angularVelocity: Double.random(in: -260...260),
                size: CGFloat.random(in: 10...18),
                color: fragmentColor(),
                spawnDate: spawn
            )
        }
    }

    /// Each fragment is a slight variation of the balloon's tint plus
    /// a few white / pale-pink accents so the confetti doesn't read
    /// as a monochrome blob.
    private func fragmentColor() -> Color {
        let roll = Int.random(in: 0..<6)
        switch roll {
        case 0:  return .white
        case 1:  return Color(red: 1.00, green: 0.85, blue: 0.92)
        default: return tint
        }
    }

    private func opacity(for p: PopParticle) -> Double {
        let age = Date().timeIntervalSince(p.spawnDate)
        let fadeFrom = Self.maxLife - 0.5
        if age < fadeFrom { return 1 }
        return max(0, 1 - (age - fadeFrom) / 0.5)
    }
}

// ─── Daily leaderboard-warning confirmation ─────────────────────────

/// Compact centered dialog shown when the player taps "show incorrect"
/// in daily mode. Asks them to confirm that they understand the
/// leaderboard-eligibility cost. Tapping the dialog's "no" button OR
/// any point outside the card dismisses with no-semantics; tapping
/// "yes" enables show-incorrect for today's puzzle.
///
/// Paired with a `FocusDim` layer at a lower zIndex in the parent
/// ZStack — that provides the "same amount as the hint" darken; this
/// view only handles the card + tap-outside plumbing.
struct DailyLeaderboardWarningDialog: View {
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        ZStack {
            // Transparent full-screen tap catcher behind the card.
            // Any tap that misses the card counts as a "no" so the
            // dialog folds back up without toggling show-incorrect.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onNo() }
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("showing incorrect disables leaderboards")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 4)

                HStack(spacing: 14) {
                    Button(action: onNo) {
                        Text("no")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .frame(minWidth: 84)
                            .frame(height: 42)
                            .background(Color.white.opacity(0.16), in: Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.30), lineWidth: 1)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Button(action: onYes) {
                        Text("yes")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .frame(minWidth: 84)
                            .frame(height: 42)
                            .background(Color(red: 0.92, green: 0.48, blue: 0.48).opacity(0.80),
                                        in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .padding(.horizontal, 40)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        }
    }
}

// ─── Daily show-answers prompt ──────────────────────────────────────

/// Shown on every daily entry (not just first) before the puzzle
/// starts. A binary decision — kept as a full-screen overlay so it
/// never gets ignored.
struct DailyShowAnswersPrompt: View {
    @Bindable var game: GameState
    let onResolved: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.80))
                Text(Strings.DailyPrompt.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(Strings.DailyPrompt.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        game.showIncorrect = false
                        game.showedIncorrect = false
                        onResolved()
                    } label: {
                        Text(Strings.DailyPrompt.keepHidden)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 22)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Button {
                        game.showIncorrect = true
                        game.showedIncorrect = true
                        onResolved()
                    } label: {
                        Text(Strings.DailyPrompt.enable)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .padding(.horizontal, 22)
                            .frame(height: 46)
                            .background(Color(red: 0.92, green: 0.48, blue: 0.48)
                                .opacity(0.75), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}
