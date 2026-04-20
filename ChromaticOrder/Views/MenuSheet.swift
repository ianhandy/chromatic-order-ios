//  Hamburger dropdown — three icon + label rows that slide in from the
//  right when the menu opens. No card or background: the rows float on
//  top of the game. Order (top → bottom): home, settings, feedback.
//  Icons arrive first, staggered top-first; each label fades in once
//  its icon has settled into place.
//
//  Always rendered in the ZStack so the close animation can play out
//  (items slide back off-screen and the labels fade). When closed,
//  hit-testing is disabled so the menu doesn't eat taps on the game.

import SwiftUI

struct MenuSheet: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool
    @Binding var creatorOpen: Bool
    @Binding var feedbackOpen: Bool
    @Binding var accessibilityOpen: Bool
    @Binding var started: Bool
    @Environment(Transitioner.self) private var transitioner

    var body: some View {
        // The "show incorrect" row only makes sense while the player
        // is still working on a zen puzzle (challenge doesn't use
        // this mechanic; on a solved board there's nothing to check).
        // Gating its `isOpen` on that condition means the row is
        // always mounted (so @State survives) but only animates in
        // when applicable.
        let canShowIncorrect = game.mode == .zen && !game.solved
        GeometryReader { _ in
            VStack(alignment: .trailing, spacing: 10) {
                MenuSheetRow(
                    icon: "house.fill",
                    label: "home",
                    index: 0,
                    isOpen: menuOpen
                ) {
                    menuOpen = false
                    transitioner.fade {
                        started = false
                    }
                }
                MenuSheetRow(
                    icon: "gearshape.fill",
                    label: "settings",
                    index: 1,
                    isOpen: menuOpen,
                    // 3-second long-press clears every lock on the
                    // current puzzle — dev cheat for iterating on
                    // generator output. Stripped from Release.
                    onLongPress: settingsLongPressAction
                ) {
                    menuOpen = false
                    accessibilityOpen = true
                }
                MenuSheetRow(
                    icon: "envelope.fill",
                    label: "feedback",
                    index: 2,
                    isOpen: menuOpen
                ) {
                    menuOpen = false
                    feedbackOpen = true
                }
                // Conditionally mount the "show incorrect" row — if
                // the mode doesn't support it (challenge, or a solved
                // zen puzzle), drop it entirely so the remaining
                // rows flex up and no empty slot is left behind. The
                // share row's index shifts accordingly.
                if canShowIncorrect {
                    MenuSheetRow(
                        icon: game.showIncorrect
                            ? "exclamationmark.triangle.fill"
                            : "exclamationmark.triangle",
                        label: game.showIncorrect
                            ? "hide incorrect"
                            : "show incorrect",
                        index: 3,
                        isOpen: menuOpen
                    ) {
                        game.toggleShowIncorrect()
                        menuOpen = false
                    }
                }
                if let p = game.puzzle {
                    MenuSheetShareRow(
                        index: canShowIncorrect ? 4 : 3,
                        isOpen: menuOpen,
                        puzzle: p
                    )
                }
                Spacer()
            }
            .padding(.trailing, 18)
            .padding(.top, 58)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(menuOpen)
    }

    /// Dev cheat wired into the settings row's 3-second long-press.
    /// Returns nil in Release so archive builds have no handler and
    /// the row behaves as a plain tap-only button.
    private var settingsLongPressAction: (() -> Void)? {
#if DEBUG
        return {
            Haptics.solve()
            game.debugUnlockAllLocks()
            menuOpen = false
        }
#else
        return nil
#endif
    }
}

/// Share variant of the hamburger row — same slide-in-from-right +
/// label-fade animation pattern as `MenuSheetRow`, but wraps a
/// SwiftUI `ShareLink` around an HTTPS URL. The URL points at
/// `https://kroma.ianhandy.com/p/<base64url>` — a Vercel serverless
/// landing page that emits OG meta tags (iMessage/Slack render a
/// visual preview card) and JS-redirects the visitor to `kroma://`
/// on iOS-with-Kromatika, or to the web version otherwise. HTTPS is
/// required here: custom `kroma://` URLs skip OG fetching so their
/// cards degrade to raw URL text. SharePreview supplies a rasterized
/// starting-state image so the sender-side share sheet also shows a
/// visual card before they pick a destination.
private struct MenuSheetShareRow: View {
    let index: Int
    let isOpen: Bool
    let puzzle: Puzzle

    @State private var iconArrived = false
    @State private var labelVisible = false
    /// Populated by a background POST to `/api/save` once the row
    /// renders. When non-nil, the share URL uses the short slug form
    /// (`/p/<slug>`) — small enough for iMessage to render a preview
    /// card. If the network POST fails or hasn't returned in time,
    /// the ShareLink falls through to the long base64 URL, which
    /// still works but may dump as raw text in the message.
    @State private var shortSlug: String? = nil

    var body: some View {
        let json = (try? CreatorCodec.encodePuzzle(puzzle)) ?? ""
        let b64 = ChromaticOrderApp.encodeBase64URL(Data(json.utf8))
        let pathSegment = shortSlug ?? b64
        let shareURL = URL(string: "https://kroma.ianhandy.com/p/\(pathSegment)")
            ?? URL(string: "https://kroma.ianhandy.com")!
        let previewImage = PuzzlePreviewRenderer.render(puzzle)
            ?? Image(systemName: "paintpalette.fill")

        ShareLink(
            item: shareURL,
            subject: Text("A Kromatika puzzle (\(puzzle.difficulty)/10)"),
            preview: SharePreview(
                "Kromatika puzzle (\(puzzle.difficulty)/10)",
                image: previewImage
            )
        ) {
            HStack(spacing: 14) {
                Text("share")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .opacity(labelVisible ? 1 : 0)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
            }
            .offset(x: iconArrived ? 0 : 280)
        }
        .task(id: json) {
            // Re-run when the puzzle JSON changes. Best-effort — any
            // failure (no network, KV down, server cold start) leaves
            // shortSlug nil and the ShareLink falls back to the long
            // base64 URL.
            shortSlug = nil
            shortSlug = await fetchShareSlug(json: json)
        }
        .onChange(of: isOpen) { _, open in
            if open {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)
                    .delay(Double(index) * 0.09)) {
                    iconArrived = true
                }
                withAnimation(.easeIn(duration: 0.45)
                    .delay(Double(index) * 0.09 + 0.40)) {
                    labelVisible = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    labelVisible = false
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.90)
                    .delay(Double(max(0, 4 - index)) * 0.06 + 0.06)) {
                    iconArrived = false
                }
            }
        }
    }

    /// POST the puzzle JSON to the share-link save endpoint and return
    /// the short slug. Returns nil on any failure so the caller falls
    /// back to the inline base64 URL.
    private func fetchShareSlug(json: String) async -> String? {
        guard !json.isEmpty,
              let url = URL(string: "https://kroma.ianhandy.com/api/save") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 4
        let body = ["json": json]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard request.httpBody != nil else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(SlugResponse.self, from: data)
            return decoded.slug
        } catch {
            return nil
        }
    }
}

private struct SlugResponse: Decodable {
    let slug: String
}

private struct MenuSheetRow: View {
    let icon: String
    let label: String
    let index: Int
    let isOpen: Bool
    /// Optional long-press handler. When non-nil, holding the row for
    /// 3 seconds fires this instead of (and instead suppresses) the
    /// tap action. Used for dev shortcuts that share a visible
    /// button with a normal user action.
    var onLongPress: (() -> Void)? = nil
    let action: () -> Void

    /// True once the icon has (animated) slid to its resting x=0 spot.
    /// Drives the icon's offset. Starts false so cold launch = closed
    /// = offscreen. Flipped by onChange when `isOpen` toggles.
    @State private var iconArrived = false
    /// True once the label has (animated) faded to opacity 1. Always
    /// trails `iconArrived` on open so the label reveals after the
    /// icon has settled.
    @State private var labelVisible = false
    /// Latched when a long-press fires so the button's tap-on-release
    /// handler knows to bow out. SwiftUI's simultaneousGesture lets
    /// both fire on a hold-then-release without this flag.
    @State private var longPressConsumed = false

    var body: some View {
        Button(action: {
            if longPressConsumed { longPressConsumed = false; return }
            action()
        }) {
            HStack(spacing: 14) {
                Text(label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .opacity(labelVisible ? 1 : 0)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.55))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
            }
            .offset(x: iconArrived ? 0 : 280)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 3.0).onEnded { _ in
                guard let handler = onLongPress else { return }
                longPressConsumed = true
                handler()
            }
        )
        .onChange(of: isOpen) { _, open in
            if open {
                // Open: icons slide in top-first, ~90ms stagger.
                // Label fades in once its icon has settled (~0.4s
                // after the slide starts).
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)
                    .delay(Double(index) * 0.09)) {
                    iconArrived = true
                }
                withAnimation(.easeIn(duration: 0.45)
                    .delay(Double(index) * 0.09 + 0.40)) {
                    labelVisible = true
                }
            } else {
                // Close: all labels fade out first; then icons
                // retract bottom-first so the list collapses toward
                // the hamburger rather than popping away together.
                withAnimation(.easeOut(duration: 0.18)) {
                    labelVisible = false
                }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.90)
                    .delay(Double(2 - index) * 0.06 + 0.06)) {
                    iconArrived = false
                }
            }
        }
    }
}
