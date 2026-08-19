//  Game Center leaderboard, with a signed-out state of our own.
//
//  `GKGameCenterViewController` presented while the player isn't
//  signed in renders as a blank sheet with no explanation — the app
//  looks broken, and there's nothing on screen saying what to do.
//  `LeaderboardView` gates on `GameCenter.shared.isAuthenticated` and
//  explains it instead, offering a retry that re-runs the
//  authentication handler (which presents Apple's own sign-in sheet
//  when one is needed).
//
//  The `GKGameCenterViewController` wrapper itself is unchanged, just
//  renamed and made private — its coordinator still forwards Game
//  Center's "done" callback to SwiftUI's `dismiss`.

import SwiftUI
import GameKit

struct LeaderboardView: View {
    let leaderboardID: String
    @Environment(\.dismiss) private var dismiss
    /// Read so SwiftUI re-evaluates when authentication lands — the
    /// handler can flip this well after the sheet is already up.
    private var gameCenter: GameCenter { GameCenter.shared }

    var body: some View {
        if gameCenter.isAuthenticated {
            GameCenterLeaderboard(leaderboardID: leaderboardID,
                                  onFinish: { dismiss() })
                .ignoresSafeArea()
        } else {
            NavigationStack {
                ContentUnavailableView {
                    Label("game center not signed in",
                          systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("leaderboards need Game Center. sign in from Settings › Game Center, then try again.")
                } actions: {
                    Button("try again") { gameCenter.authenticate() }
                        .buttonStyle(.borderedProminent)
                }
                .kromaSheet(Strings.Menu.leaderboard) { dismiss() }
            }
        }
    }
}

private struct GameCenterLeaderboard: UIViewControllerRepresentable {
    let leaderboardID: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let vc = GKGameCenterViewController(
            leaderboardID: leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        vc.gameCenterDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: GKGameCenterViewController, context: Context) {}

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func gameCenterViewControllerDidFinish(_ gcViewController: GKGameCenterViewController) {
            onFinish()
        }
    }
}
