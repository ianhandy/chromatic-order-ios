//  The one place layout numbers, chrome surfaces, and type choices are
//  decided. Everything visual in the app is meant to come from here so
//  a change of rhythm is a change in one file rather than a sweep of
//  magic numbers across twenty views.
//
//  Two rules the rest of the app leans on:
//
//  • Type is always a semantic text style. Kromatika's character is the
//    rounded SF face, not a pixel size, so `Kroma.font` picks the design
//    and lets Dynamic Type pick the size. Nothing here returns a fixed
//    point size, which is what keeps the accessibility sizes readable.
//  • Chrome never hard-codes white. The in-game surfaces sit on the
//    player's puzzle, so they read their strength from the environment
//    (Increase Contrast, Reduce Transparency) instead of one baked
//    opacity that only looks right in the default configuration.

import SwiftUI

enum Kroma {

    /// 8-point rhythm with 4-point optical steps. A team convention, not
    /// an Apple mandate — but applied consistently it is what makes
    /// unrelated screens read as one app.
    enum Space {
        static let hairline: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        /// Outer margin for full-bleed game content. Matches the grid's
        /// own horizontal inset so the board and the chrome above it
        /// share one left edge.
        static let screenMargin: CGFloat = 20
    }

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 16
        static let panel: CGFloat = 20
    }

    enum Metrics {
        /// Apple's minimum comfortable target. Visible chrome is often
        /// smaller than this; the *hit region* never is.
        static let minTarget: CGFloat = 44
        /// Visible height of a top-bar chip or icon button at the
        /// default text size. Grows with Dynamic Type because the
        /// content inside it does — this is a floor, never a cap.
        static let chromeControl: CGFloat = 36
    }

    // MARK: - Type

    /// A semantic text style in Kromatika's rounded face.
    ///
    /// Always prefer this over `.system(size:)`. The rounded design is
    /// the brand; the size belongs to the player.
    static func font(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }

    /// Monospaced digits at a semantic size — timers, counters, scores.
    /// Same scaling contract as `font`, different face so numbers don't
    /// jitter as they tick.
    static func monoFont(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

// MARK: - Chrome surfaces

/// Strength of an in-game chrome surface. The game paints its own black
/// backdrop, so these are luminance steps over that rather than system
/// materials — but they still answer to Increase Contrast, which is the
/// part that matters for legibility over a bright puzzle.
enum KromaSurface {
    /// A resting control: level chip, icon button.
    case control
    /// A control the player has engaged — menu open, filter active.
    case controlActive
    /// A floating panel that must stay readable over the board.
    case panel

    fileprivate func fill(contrast: ColorSchemeContrast) -> Color {
        let high = contrast == .increased
        switch self {
        case .control:       return .white.opacity(high ? 0.20 : 0.08)
        case .controlActive: return .white.opacity(high ? 0.34 : 0.18)
        case .panel:         return .black.opacity(high ? 0.95 : 0.82)
        }
    }

    fileprivate func stroke(contrast: ColorSchemeContrast) -> Color {
        let high = contrast == .increased
        switch self {
        case .control, .controlActive: return .white.opacity(high ? 0.65 : 0.25)
        case .panel:                   return .white.opacity(high ? 0.55 : 0.18)
        }
    }
}

private struct KromaSurfaceModifier<S: InsettableShape>: ViewModifier {
    let surface: KromaSurface
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(surface.fill(contrast: contrast), in: shape)
            .overlay(shape.strokeBorder(surface.stroke(contrast: contrast), lineWidth: 1))
    }
}

extension View {
    /// Paint one of the app's standard chrome surfaces behind this view.
    func kromaSurface<S: InsettableShape>(_ surface: KromaSurface, in shape: S) -> some View {
        modifier(KromaSurfaceModifier(surface: surface, shape: shape))
    }

    func kromaSurface(_ surface: KromaSurface) -> some View {
        kromaSurface(surface, in: Capsule())
    }

    /// Guarantee a 44×44 hit region regardless of how small the visible
    /// glyph is. Applied to the *label*, inside the button, so the
    /// button's own highlight covers the whole region.
    func kromaHitTarget() -> some View {
        frame(minWidth: Kroma.Metrics.minTarget,
              minHeight: Kroma.Metrics.minTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Controls

/// The app's standard button feel: a brief inset on press, and a clearly
/// non-interactive treatment when disabled. Custom buttons elsewhere in
/// the app had no pressed state at all, so taps on the top bar felt dead.
struct KromaControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.94)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KromaControlButtonStyle {
    static var kromaControl: KromaControlButtonStyle { KromaControlButtonStyle() }
}

// MARK: - Motion

extension View {
    /// Run an animation only when the player hasn't asked for less
    /// motion. State still changes either way — only the tween is
    /// dropped — so nothing depends on the animation completing.
    func kromaAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(KromaMotionModifier(animation: animation, value: value))
    }
}

private struct KromaMotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Sheet chrome

/// One presentation contract for every modal in the app.
///
/// Before this, nine sheets dismissed via four different words ("Done",
/// "Close", "close", "cancel") in three different toolbar slots, so the
/// way out of a screen had to be re-learned each time. Now: the title is
/// lowercase like the rest of Kromatika's voice, and the way out is
/// always `done`, always top-trailing.
struct KromaSheetChrome: ViewModifier {
    let title: String
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("done", action: dismiss)
                        .font(Kroma.font(.body, .semibold))
                }
            }
    }
}

extension View {
    /// Standard title + dismissal for a modally presented screen.
    func kromaSheet(_ title: String, dismiss: @escaping () -> Void) -> some View {
        modifier(KromaSheetChrome(title: title, dismiss: dismiss))
    }
}
