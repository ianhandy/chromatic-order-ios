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
            .font(Kroma.font(.title3, .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
            .padding(.vertical, Kroma.Space.l)
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
///   alive         — idle sway
///   released      — floats up and off-screen (auto-dismiss), then calls `onFinished`
enum TutorialBalloonExit: Equatable {
    case alive
    case released
}

/// Cartoon-balloon-shaped tutorial bubble. Replaces the flat
/// TutorialTooltip when reduce-motion is off. Physics are deliberately
/// lightweight — passive sway + float-away — just enough to read as a
/// floating thing with some whimsy. Reduce-motion users see the flat tooltip.
struct TutorialBalloon: View {
    let text: String
    let tint: Color
    /// `.alive` while the tutorial is live; flips to `.released` on
    /// normal dismissal (menu open, first-placement, level change).
    let exit: TutorialBalloonExit
    /// Called when the balloon's exit animation completes so the
    /// parent can unmount it + clear the flag.
    let onFinished: () -> Void
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
    /// Guards `onFinished()` so at most one call fires per lifecycle.
    @State private var finishedFired: Bool = false
    private static let balloonSize = CGSize(width: 150, height: 170)
    private static let knotHeight: CGFloat = 10
    /// Length of the dangling string below the knot.
    private static let stringLength: CGFloat = 50

    var body: some View {
        // TimelineView drives passive per-frame sway and float-away
        // motion. The closure only reads the latest pose from `computePose`.
        // 30 Hz is plenty: the fastest term in `computePose` completes a
        // cycle in ~3.5 s, so the extra 30 frames a second bought nothing
        // but a busier display link behind a live puzzle.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
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
        .allowsHitTesting(false)
        // Initialise appearAt once at mount so computePose has a
        // stable birth date without scheduling async state mutations
        // from inside the TimelineView body (which can cause "modifying
        // state during view update" crashes when the app returns from
        // background and the timeline fires multiple frames rapidly).
        .onAppear { if appearAt == nil { appearAt = Date() } }
        // Capture the exit-start timestamp the moment the balloon
        // transitions out of its idle state.
        .onChange(of: exit) { _, newExit in
            if newExit != .alive && exitStartedAt == nil {
                exitStartedAt = Date()
            }
        }
    }

    @ViewBuilder
    private var balloonVisual: some View {
        // The tutorial "balloon" is now a floating soap bubble: a
        // translucent sphere with a bright rim and a couple of specular
        // glints, text suspended inside. No knot, no dangling string —
        // it reads as a bubble that drifts upward when let go, matching
        // the game's glassy theme rather than a party balloon.
        let d = Self.balloonSize.width      // bubble diameter
        let r = d / 2
        ZStack {
            // Bubble body — mostly transparent with the tint pooling at
            // the rim, so the puzzle backdrop shows through the middle
            // the way light passes through a real bubble film.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.30),
                            tint.opacity(0.16),
                            tint.opacity(0.10),
                            tint.opacity(0.26),
                        ],
                        center: UnitPoint(x: 0.36, y: 0.30),
                        startRadius: 2,
                        endRadius: r * 1.02
                    )
                )
                .overlay(
                    // Iridescent rim — bright on the lit side, fading
                    // into the tint on the far side.
                    Circle().strokeBorder(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.25),
                                tint.opacity(0.45),
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.85),
                            ],
                            center: .center
                        ),
                        lineWidth: 1.5
                    )
                )
                .frame(width: d, height: d)
                .shadow(color: tint.opacity(0.30), radius: 14, y: 4)
            // Primary specular glint — soft streak in the upper-left.
            Ellipse()
                .fill(Color.white.opacity(0.55))
                .frame(width: d * 0.20, height: d * 0.12)
                .rotationEffect(.degrees(-38))
                .offset(x: -d * 0.22, y: -d * 0.24)
                .blur(radius: 0.5)
                .allowsHitTesting(false)
            // Secondary tiny glint for that wet-bubble read.
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: d * 0.06, height: d * 0.06)
                .offset(x: -d * 0.30, y: -d * 0.08)
                .allowsHitTesting(false)
            // Text suspended in the bubble. A drop shadow keeps it
            // legible against the translucent film + busy backdrop.
            Text(text)
                .font(Kroma.font(.body, .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .frame(width: d - 18, alignment: .center)
                .shadow(color: .black.opacity(0.50), radius: 3, y: 1)
            // Up-left corner pointer — only when the parent wires it in
            // (zen-intro). Sits inside the bubble's upper-left arc.
            if cornerArrow {
                Image(systemName: "arrow.up.left")
                    .font(Kroma.font(.headline, .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.30), radius: 1.5, y: 1)
                    .offset(x: -d * 0.26, y: -d * 0.26)
                    .allowsHitTesting(false)
            }
            // Pointer anchor — bottom of the bubble. The overlay's
            // string-to-target curve starts here (zen-intro arrow to
            // the level chip); kept so that pointer still tracks.
            Color.clear
                .frame(width: 1, height: 1)
                .offset(y: r)
                .transformAnchorPreference(
                    key: TutorialAnchorsKey.self,
                    value: .bounds
                ) { [knotAnchorKey] value, anchor in
                    value[knotAnchorKey] = anchor
                }
        }
    }

    /// One-tick snapshot of the balloon's current visual pose —
    /// composition of idle sway and release animation.
    private struct BalloonPose {
        var offset: CGSize
        var angle: Double
        var scale: CGFloat
        var opacity: Double
    }

    /// The released balloon starts almost standstill, accelerates smoothly
    /// to terminal velocity over `accelDuration`, then coasts. Returns the
    /// cumulative displacement along one axis at time `dt`.
    private static func accelThenCoast(dt: TimeInterval, terminalV: Double,
                                       accelDuration: TimeInterval = 0.35) -> Double {
        if dt <= 0 { return 0 }
        if dt < accelDuration {
            // Constant acceleration a = terminalV / accelDuration.
            // Displacement = 0.5 * a * dt^2.
            let a = terminalV / accelDuration
            return 0.5 * a * dt * dt
        }
        // Accel phase done — add constant-velocity coast.
        let accelDist = 0.5 * terminalV * accelDuration
        return accelDist + terminalV * (dt - accelDuration)
    }

    private func computePose(at t: Date) -> BalloonPose {
        let birth = appearAt ?? t
        let age = t.timeIntervalSince(birth)
        let isIdle = exit == .alive
        // Sway — bigger amplitude + slower frequency reads as a
        // lighter, floatier balloon instead of a tethered ornament.
        // Alive balloons sway; exit motion is still.
        let swayAmp: Double = {
            switch exit {
            case .alive:    return 1.0
            case .released: return 0
            }
        }()
        let swayX = swayAmp * sin(age * 0.65) * 9.0
        let swayY = swayAmp * cos(age * 0.45) * 6.5
        let swayAngle = swayAmp * sin(age * 0.40) * 3.5
        // Exit animations.
        var floatX: CGFloat = 0
        var floatY: CGFloat = 0
        var floatAngle: Double = 0
        var exitOpacity: Double = 1
        if !isIdle {
            let started = exitStartedAt ?? t
            let dt = t.timeIntervalSince(started)
            switch exit {
            case .released:
                // Auto-dismiss (level change / menu / first placement).
                // It hangs, then builds speed so it clears the screen
                // without ever popping into a constant-speed jump.
                let disp = Self.accelThenCoast(dt: dt, terminalV: 150,
                                               accelDuration: 1.5)
                let drift = sin(dt * 1.3 + age) * 24
                floatX = CGFloat(drift)
                floatY = -CGFloat(disp)
                floatAngle = sin(dt * 1.8) * 6
                exitOpacity = max(0, 1 - dt / 3.2)
                if dt > 3.4 && !finishedFired {
                    DispatchQueue.main.async {
                        guard !self.finishedFired else { return }
                        self.finishedFired = true
                        self.onFinished()
                    }
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
            scale: 1,
            opacity: exitOpacity
        )
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

// ─── Daily leaderboard-warning confirmation ─────────────────────────

/// Compact centered dialog shown when the player taps "show incorrect"
/// in daily mode. Asks them to confirm that they understand the
/// leaderboard-eligibility cost. Tapping the dialog's "no" button OR
/// any point outside the card dismisses with no-semantics; tapping
/// "yes" enables show-incorrect for today's puzzle.
// ─── Daily show-answers prompt ──────────────────────────────────────

/// Shown on every daily entry (not just first) before the puzzle
/// starts. A binary decision — kept as a full-screen overlay so it
/// never gets ignored.
struct DailyShowAnswersPrompt: View {
    @Bindable var game: GameState
    let onResolved: () -> Void

    /// Base size for the prompt's glyph. `@ScaledMetric` so it grows
    /// with Dynamic Type instead of sitting fixed at 44pt.
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(.white.opacity(0.80))
                Text(Strings.DailyPrompt.title)
                    .font(Kroma.font(.title, .heavy))
                    .foregroundStyle(.white)
                Text(Strings.DailyPrompt.body)
                    .font(Kroma.font(.subheadline, .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Kroma.Space.xl)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        game.showIncorrect = false
                        game.showedIncorrect = false
                        onResolved()
                    } label: {
                        Text(Strings.DailyPrompt.keepHidden)
                            .font(Kroma.font(.subheadline, .bold))
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
                            .font(Kroma.font(.subheadline, .bold))
                            .padding(.horizontal, 22)
                            .frame(height: 46)
                            .background(Color(red: 0.92, green: 0.48, blue: 0.48)
                                .opacity(0.75), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, Kroma.Space.xxl)
            }
            .padding(.horizontal, Kroma.Space.xl)
        }
        .transition(.opacity)
    }
}
