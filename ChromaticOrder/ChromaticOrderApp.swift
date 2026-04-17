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
                if url.scheme == "kroma" {
                    handleKromaURL(url)
                } else {
                    handleFileURL(url)
                }
            }
        }
    }

    /// File-drop entry: `.kroma` tap in Files / Mail / AirDrop. iOS
    /// routes the URL here via the UTI declaration; the URL is a
    /// local file path, so we read + decode it directly.
    private func handleFileURL(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let doc = try? CreatorCodec.decode(data) else { return }
        guard let puzzle = CreatorCodec.rebuild(doc) else { return }
        incomingPuzzle = puzzle
        // Opening a .kroma file from outside the app counts as
        // starting — skip the menu, drop into the puzzle.
        started = true
    }

    /// Scheme entry: `kroma://play?data=<base64url-json>`. The puzzle
    /// JSON rides inline — works in any channel that renders tappable
    /// URLs (Messages, Slack, mail body, QR codes). Base64-url variant
    /// (`-`/`_`, no padding) keeps the URL short and copy-pasteable.
    private func handleKromaURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataItem = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let bytes = Self.decodeBase64URL(dataItem),
              let doc = try? CreatorCodec.decode(bytes),
              let puzzle = CreatorCodec.rebuild(doc)
        else { return }
        incomingPuzzle = puzzle
        started = true
    }

    static func decodeBase64URL(_ s: String) -> Data? {
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Standard base64 requires a multiple-of-4 length; URL-safe
        // encodes typically drop the padding, so restore it.
        while b64.count % 4 != 0 { b64 += "=" }
        return Data(base64Encoded: b64)
    }

    static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
