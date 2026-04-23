//  Game Center integration — authenticates the local player once on
//  launch and submits per-metric daily leaderboards (solve time +
//  move count). The old cumulative points/"score" leaderboards were
//  removed when the points system went away.
//
//  If Game Center isn't configured (or the user isn't signed in),
//  every submission is a silent no-op — the game still works.

import Foundation
import GameKit
import UIKit

@MainActor
final class GameCenter {
    static let shared = GameCenter()

    /// Daily solve-time leaderboard. Low-to-high, recurring daily,
    /// integer format (seconds). Submit ONCE on solve so retries
    /// don't overwrite a better run — Game Center already keeps the
    /// best submission per player per period.
    static let dailyTimeLeaderboardID = "com.ianhandy.kroma.daily_time"
    /// Daily move-count leaderboard. Low-to-high, recurring daily,
    /// integer format. Counts only swatches landing on the board
    /// (excludes bank shuffles and bank-slot swaps).
    static let dailyMovesLeaderboardID = "com.ianhandy.kroma.daily_moves"

    // ─── Achievement identifiers ────────────────────────────────────
    //
    // Each string below must match an Achievement identifier created
    // in App Store Connect under this app's Game Center configuration.
    // All achievements are one-shot (100% on first trigger), hidden
    // by default, and have intentionally lowercase player-visible
    // titles. Description / pre-earn copy is suppressed in ASC so
    // players only see the achievement surface as a surprise pop.
    enum Achievement {
        /// Player popped a tutorial balloon with a tap.
        static let poppedBalloon = "com.ianhandy.kroma.ach.how_could_you"
        /// Player let the main-menu "chill ramp" reach full — the
        /// background text fades out completely.
        static let chillMaxed = "com.ianhandy.kroma.ach.nice_isnt_it"
        /// Player saved a custom puzzle through the creator.
        static let createdLevel = "com.ianhandy.kroma.ach.creationism"
        /// Player saved a solved-grid image to their Photos library.
        static let savedImage = "com.ianhandy.kroma.ach.yoink"
        /// Player opened the stats sheet.
        static let openedStats = "com.ianhandy.kroma.ach.narcissism"
        /// Player favorited a puzzle via the top-bar star button.
        static let favoritedLevel = "com.ianhandy.kroma.ach.favoritism"
    }

    /// True once `authenticateHandler` has reported a signed-in
    /// player. Score submits silently no-op until this flips true.
    private(set) var isAuthenticated = false
    /// Local guard so a single session doesn't spam Game Center with
    /// repeat 100% reports — useful for achievements that can trigger
    /// repeatedly (balloon pops, image saves, stats-sheet opens). Game
    /// Center already dedupes server-side, but short-circuiting here
    /// saves needless round trips.
    private var reportedThisSession: Set<String> = []

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

    /// Submit solve-time (seconds) + move-count for today's daily to
    /// the per-metric recurring leaderboards. Call once on solve; Game
    /// Center retains the player's best per recurrence period so
    /// later retries of the same date don't overwrite a better run.
    func submitDailySolveMetrics(timeSec: Int, moves: Int) {
        guard isAuthenticated else { return }
        if timeSec > 0 {
            GKLeaderboard.submitScore(
                timeSec,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.dailyTimeLeaderboardID]
            ) { _ in }
        }
        if moves > 0 {
            GKLeaderboard.submitScore(
                moves,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.dailyMovesLeaderboardID]
            ) { _ in }
        }
    }

    /// Report a one-shot (100%-complete) achievement. Silent no-op
    /// until Game Center authenticates. `showsCompletionBanner = true`
    /// lets the system draw the built-in banner so the player sees a
    /// notification the first time they earn each achievement.
    func reportAchievement(_ identifier: String) {
        guard isAuthenticated else { return }
        if reportedThisSession.contains(identifier) { return }
        reportedThisSession.insert(identifier)
        let ach = GKAchievement(identifier: identifier)
        ach.percentComplete = 100.0
        ach.showsCompletionBanner = true
        GKAchievement.report([ach]) { _ in }
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
