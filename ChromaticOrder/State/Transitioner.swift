//  App-level crossfade controller. Drives a single black overlay
//  whose opacity any view can animate up to 1 during a navigation,
//  run a state mutation at the peak, then animate back down to 0.
//  Used for the main-menu ⇄ game transitions so picking a mode or
//  backing out both read as "curtain down, next scene, curtain up."

import SwiftUI

@MainActor
@Observable
final class Transitioner {
    var overlayOpacity: Double = 0

    /// Total fade-to-black duration. Matches fade-from-black so the
    /// curtain feels symmetric.
    var halfDuration: Double = 0.32

    /// Fade the overlay to fully black, run `action`, then fade back.
    /// The caller's state mutation lands exactly when the screen is
    /// fully black — no flash of the outgoing view, no flash of the
    /// incoming view. Calls after the fade-up don't overlap with the
    /// fade-down.
    func fade(_ action: @escaping () -> Void) {
        withAnimation(.easeInOut(duration: halfDuration)) {
            overlayOpacity = 1
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ns = UInt64(self.halfDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            action()
            withAnimation(.easeInOut(duration: self.halfDuration)) {
                self.overlayOpacity = 0
            }
        }
    }
}
