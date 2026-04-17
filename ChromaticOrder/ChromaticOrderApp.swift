import SwiftUI

@main
struct ChromaticOrderApp: App {
    /// Puzzle extracted from a tapped .kroma file, waiting to be
    /// handed to GameState. Set by onOpenURL, consumed by ContentView.
    @State private var incomingPuzzle: Puzzle?

    var body: some Scene {
        WindowGroup {
            ContentView(incomingPuzzle: $incomingPuzzle)
                .onOpenURL { url in
                    // Fires when the system routes a .kroma file to
                    // us — Mail / Files / AirDrop / Safari downloads
                    // all hit this path after the user picks "Open in
                    // Kroma." Read the file, decode via CreatorCodec,
                    // stash the rebuilt Puzzle; ContentView watches
                    // for a non-nil value and loads it via GameState.
                    guard let data = try? Data(contentsOf: url) else { return }
                    guard let doc = try? CreatorCodec.decode(data) else { return }
                    guard let puzzle = CreatorCodec.rebuild(doc) else { return }
                    incomingPuzzle = puzzle
                }
        }
    }
}
