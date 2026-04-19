//  SwiftUI wrapper around GKGameCenterViewController so the
//  leaderboard can be presented as a sheet from the main menu.
//  The coordinator handles Game Center's "done" callback and
//  forwards it to SwiftUI's `dismiss` action.

import SwiftUI
import GameKit

struct LeaderboardView: UIViewControllerRepresentable {
    let leaderboardID: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
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
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func gameCenterViewControllerDidFinish(_ gcViewController: GKGameCenterViewController) {
            dismiss()
        }
    }
}
