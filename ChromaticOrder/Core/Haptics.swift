//  Taptic Engine triggers for gameplay events. Uses UIFeedbackGenerator
//  for single-shot taps and CoreHaptics for richer multi-event patterns
//  (solve celebration). Respects the player's reduce-motion toggle —
//  GameState flips `isEnabled` so a11y-conscious players get a quiet UI.

import CoreHaptics
import UIKit

@MainActor
enum Haptics {
    /// Master gate. GameState sets this from `!reduceMotion` on load
    /// and on every toggle, so the haptics track the same accessibility
    /// preference that disables animations.
    static var isEnabled: Bool = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        do {
            let e = try CHHapticEngine()
            try e.start()
            // Auto-restart on interruption (Siri, phone call, etc.)
            e.resetHandler = { try? e.start() }
            return e
        } catch {
            return nil
        }
    }()

    static func pickup() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.8)
    }

    static func place() {
        guard isEnabled else { return }
        medium.impactOccurred()
    }

    /// Correct placement — crisp rigid tap so the player feels the
    /// "click into place" beyond the audio cue.
    static func placeCorrect() {
        guard isEnabled else { return }
        rigid.impactOccurred(intensity: 0.9)
    }

    /// Wrong placement — warning pattern. Used when the player's
    /// placement doesn't match the solution (mistake counter bumps).
    static func placeWrong() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
    }

    /// Shake gesture echo — matches the shake-to-shuffle action.
    static func shake() {
        guard isEnabled else { return }
        medium.impactOccurred(intensity: 0.7)
    }

    /// Balloon pop — short, high-sharpness transient so it reads as
    /// an impact rather than the crisp "click" of a placement. Falls
    /// back to the rigid impact generator on devices without CoreHaptics.
    static func pop() {
        guard isEnabled else { return }
        guard let engine else {
            rigid.impactOccurred(intensity: 1.0)
            return
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95),
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            rigid.impactOccurred(intensity: 1.0)
        }
    }

    /// Solved-puzzle celebration — three ascending taps. Falls back to
    /// the system success notification on devices without CoreHaptics.
    static func solve() {
        guard isEnabled else { return }
        guard let engine else {
            notification.notificationOccurred(.success)
            return
        }
        let intensities: [Float] = [0.7, 0.85, 1.0]
        let sharpnesses: [Float] = [0.4, 0.6, 0.85]
        let events: [CHHapticEvent] = (0..<3).map { i in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensities[i]),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpnesses[i]),
                ],
                relativeTime: Double(i) * 0.10
            )
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            notification.notificationOccurred(.success)
        }
    }
}
