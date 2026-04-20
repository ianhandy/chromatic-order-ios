import SwiftUI

@main
struct ChromaticOrderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var incomingPuzzle: Puzzle?
    /// false on cold launch → show MenuView. Flipped to true when the
    /// player picks zen or challenge from the menu. In-game "Back to
    /// menu" flips it back via Transitioner.
    @State private var started: Bool = false
    @State private var game = GameState()
    /// Drives the app-level fade-to-black overlay so navigation
    /// between the menu and the game is a symmetric crossfade.
    @State private var transitioner = Transitioner()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if started {
                        ContentView(game: game,
                                    incomingPuzzle: $incomingPuzzle,
                                    started: $started)
                    } else {
                        MenuView(game: game, started: $started)
                    }
                }
                // Force dark color scheme app-wide. The game's menus
                // and game view paint explicit black backgrounds,
                // but sheet-based views (CreatorView, AccessibilitySheet,
                // ColorPickerSheet, GalleryView) rely on system chrome
                // which in Light Mode renders as a white background —
                // a tester on a light-mode device reported the creator
                // screen coming up all-white. Pinning dark mode keeps
                // the visuals consistent across devices.
                .preferredColorScheme(.dark)
                // Black curtain — hoisted above every screen in the
                // ZStack so the fade reads on top of both menu and
                // game. Ignores hit testing while clear so it never
                // eats taps outside of a transition.
                Color.black
                    .opacity(transitioner.overlayOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(transitioner.overlayOpacity > 0.01)
            }
            .environment(transitioner)
            .onAppear {
                // Kick off Game Center sign-in once per process —
                // handler resolves to a no-op if GC is unavailable
                // or the player declines, so everything downstream
                // (score submit, leaderboard view) simply stays idle.
                GameCenter.shared.authenticate()
                // Pull progress + stats from iCloud (and wire a
                // listener for later external updates). Cloud wins on
                // cold launch so switching devices keeps the player
                // where they left off.
                CloudSync.start()
            }
            .onOpenURL { url in
                if url.scheme == "kroma" {
                    handleKromaURL(url)
                } else if url.scheme == "https" && url.host == "kroma.ianhandy.com" {
                    handleUniversalLink(url)
                } else {
                    handleFileURL(url)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Returning from background: iOS may have torn down the
                // AVAudioEngine graph (interruption). Rebuild so the
                // first play() call after resume doesn't crash on a
                // stale node.
                if phase == .active {
                    GlassyAudio.shared.appDidBecomeActive()
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

    /// Universal Link entry: `https://kroma.ianhandy.com/p/<slug>`.
    /// Paths are declared in `/.well-known/apple-app-site-association`
    /// on the server; iOS routes matching taps straight into the app,
    /// skipping Safari entirely. Resolves the slug server-side via
    /// `/api/fetch/<slug>` to get the raw JSON, then loads the puzzle
    /// with the same pipeline as the kroma:// scheme.
    private func handleUniversalLink(_ url: URL) {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "p" else { return }
        let slug = String(parts[1])
        guard (6...10).contains(slug.count) else { return }
        Task { await fetchAndLoadSlug(slug) }
    }

    /// Resolve a share slug against `/api/fetch/<slug>`, then decode +
    /// rebuild the puzzle. Best-effort — network failure / expired
    /// slug silently no-ops; the user stays on whichever screen they
    /// were on rather than getting bounced.
    private func fetchAndLoadSlug(_ slug: String) async {
        guard let url = URL(string: "https://kroma.ianhandy.com/api/fetch/\(slug)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(SlugFetchResponse.self, from: data)
            guard let bytes = decoded.json.data(using: .utf8),
                  let doc = try? CreatorCodec.decode(bytes),
                  let puzzle = CreatorCodec.rebuild(doc) else { return }
            await MainActor.run {
                incomingPuzzle = puzzle
                started = true
            }
        } catch {
            return
        }
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

private struct SlugFetchResponse: Decodable {
    let json: String
}
