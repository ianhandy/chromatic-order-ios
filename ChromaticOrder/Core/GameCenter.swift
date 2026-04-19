//  Game Center integration — authenticates the local player once on
//  launch, submits challenge-mode scores, and exposes a leaderboard
//  ID for the viewer view to pull from.
//
//  App Store Connect setup required:
//    1. Enable Game Center for the app.
//    2. Create a leaderboard with identifier matching
//       `GameCenter.challengeLeaderboardID` below.
//    3. Configure sort order = high-to-low, format type = integer,
//       and a default localization.
//
//  If Game Center isn't configured (or the user isn't signed in),
//  every submission is a silent no-op — the game still works.

import Foundation
import GameKit
import UIKit

@MainActor
final class GameCenter {
    static let shared = GameCenter()

    /// App Store Connect leaderboard identifier for the challenge
    /// mode's high score. Must match the value you set up when
    /// creating the leaderboard in App Store Connect exactly.
    static let challengeLeaderboardID = "com.ianhandy.kroma.challenge_score"

    /// True once `authenticateHandler` has reported a signed-in
    /// player. Score submits silently no-op until this flips true.
    private(set) var isAuthenticated = false

    private init() {}

    /// Start the one-time authentication flow. Safe to call from
    /// onAppear — if Game Center has the player signed in already,
    /// the handler fires immediately with no UI. If a sign-in sheet
    /// is needed, we present it via the active key window.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let vc = vc {
                    self.present(vc)
                } else if GKLocalPlayer.local.isAuthenticated {
                    self.isAuthenticated = true
                } else {
                    self.isAuthenticated = false
                }
            }
        }
    }

    /// Submit a challenge-mode score. Only the player's best is
    /// retained on the server, so we can safely submit on every
    /// level-complete without tracking a local high-score watermark.
    func submitChallengeScore(_ score: Int) {
        guard isAuthenticated, score > 0 else { return }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [Self.challengeLeaderboardID]
        ) { _ in }
    }

    private func present(_ vc: UIViewController) {
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first,
              let root = keyWindow.rootViewController else { return }
        // Find the top-most presented VC so we don't try to present
        // on top of an already-presenting controller.
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
}
