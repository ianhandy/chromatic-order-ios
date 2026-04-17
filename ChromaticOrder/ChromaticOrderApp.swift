import SwiftUI

@main
struct ChromaticOrderApp: App {
    @State private var incomingPuzzle: Puzzle?
    /// false on cold launch → show MenuView. Flipped to true when the
    /// player picks zen or challenge from the menu. In-game "Back to
    /// menu" would flip it back (not wired yet — future work).
    @State private var started: Bool = false
    @State private var game = GameState()

    var body: some Scene {
        WindowGroup {
            Group {
                if started {
                    ContentView(game: game,
                                incomingPuzzle: $incomingPuzzle,
                                started: $started)
                } else {
                    MenuView(game: game, started: $started)
                }
            }
            .onOpenURL { url in
                guard let data = try? Data(contentsOf: url) else { return }
                guard let doc = try? CreatorCodec.decode(data) else { return }
                guard let puzzle = CreatorCodec.rebuild(doc) else { return }
                incomingPuzzle = puzzle
                // Opening a .kroma file from outside the app counts as
                // starting — skip the menu, drop into the puzzle.
                started = true
            }
        }
    }
}
