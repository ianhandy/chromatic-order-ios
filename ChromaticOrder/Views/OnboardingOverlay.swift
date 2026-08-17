//  One-shot first-run hint. Shows a single capsule tooltip above the
//  grid on zen-mode level 1 the very first time a player opens the
//  app, then marks itself seen on the first correct placement — so the
//  onboarding goes away without the player having to dismiss it.

import SwiftUI

struct OnboardingOverlay: View {
    @Bindable var game: GameState
    @AppStorage("onboardingSeen_v1") private var seen: Bool = false

    var body: some View {
        if !seen, shouldShow {
            VStack {
                Text("drag a swatch onto any cell")
                    .font(Kroma.font(.callout, .semibold))
                    .tracking(0.6)
                    .textCase(.lowercase)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Kroma.Space.l)
                    .padding(.vertical, Kroma.Space.s)
                    .kromaSurface(.panel, in: Capsule())
                    .padding(.horizontal, Kroma.Space.xl)
                    .padding(.top, 92)
                Spacer()
            }
            .transition(.opacity)
            .allowsHitTesting(false)
            .onChange(of: game.gameplayGuidanceDismissalID) { _, _ in
                seen = true
            }
        }
    }

    private var shouldShow: Bool {
        // Campaign levels do their own teaching, one line at a time, so the
        // generic zen hint would just talk over them.
        game.campaignIndex == nil
            && game.mode == .zen
            && game.level == 1
            && !game.solved
            && !game.generating
            && game.puzzle != nil
    }
}
