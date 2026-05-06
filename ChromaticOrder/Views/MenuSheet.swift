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
    @Binding var communityOpen: Bool
    @Binding var started: Bool
    @Environment(Transitioner.self) private var transitioner

    var body: some View {
        // The "show incorrect" row is available in zen (free) and
        // daily (available but using it disqualifies the leaderboard
        // submission — handled in GameState.handleNext). Challenge
        // mode hides the row entirely: players reveal incorrect cells
        // by pressing Check, which costs a heart on failure — that
        // IS the challenge-mode "show incorrect" path. Nothing to
        // check when the puzzle is already solved.
        let canShowIncorrect = game.mode != .challenge && !game.solved
        ZStack(alignment: .topTrailing) {
            // Dismiss scrim — transparent full-screen catcher that
            // sits behind the rows and eats every tap reaching
            // MenuSheet's z-layer while open. Closes the menu without
            // firing any game action below (cells, bank, top bar).
            // Hit-testing is gated on menuOpen so it doesn't block
            // the game when the menu is closed. Rows are layered
            // above and handle their own close-then-act.
            if menuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { menuOpen = false }
            }

            VStack(alignment: .trailing, spacing: 10) {
                // Home row morphs into "← gallery" when the current
                // puzzle was loaded from the Gallery sheet so the
                // return path matches the entry path. The gallery
                // auto-re-opens via GameState.openGalleryOnMenuAppear
                // which MenuView consumes on appear.
                if game.cameFromGallery {
                    MenuSheetRow(
                        icon: "square.grid.2x2.fill",
                        label: "gallery",
                        index: 0,
                        isOpen: menuOpen
                    ) {
                        menuOpen = false
                        game.openGalleryOnMenuAppear = true
                        transitioner.fade {
                            started = false
                        }
                    }
                } else {
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
                // Community access is currently surfaced from the
                // Gallery's top bar instead of the in-game hamburger.
                // Row kept here behind a flag so the staggered-row
                // animation indices stay grouped if we re-enable it.
                let showCommunityRow = false
                if showCommunityRow {
                    MenuSheetRow(
                        icon: "person.2.fill",
                        label: "community",
                        index: 2,
                        isOpen: menuOpen
                    ) {
                        menuOpen = false
                        communityOpen = true
                    }
                }
                MenuSheetRow(
                    icon: "envelope.fill",
                    label: "feedback",
                    index: 3,
                    isOpen: menuOpen
                ) {
                    menuOpen = false
                    feedbackOpen = true
                }
                // Always mount the "show incorrect" row so the menu
                // layout stays stable across state transitions (e.g.
                // tapping Next Level with the menu open would make
                // the row vanish and the share row shift, leaving a
                // visible blank). When the row isn't meaningful
                // (challenge mode, or a solved puzzle) we dim +
                // disable instead of unmounting.
                ShowIncorrectMenuRow(
                    game: game,
                    index: 4,
                    isOpen: menuOpen,
                    disabled: !canShowIncorrect,
                    onTapPrimary: {
                        // In daily mode, enabling show-incorrect
                        // voids leaderboard eligibility — close the
                        // hamburger and pop the confirmation dialog
                        // on the main game screen so the player sees
                        // the full "disables leaderboards" copy with
                        // the darkened backdrop, rather than an
                        // inline "are you sure?" tucked into the menu.
                        if game.mode == .daily && !game.showIncorrect {
                            game.dailyShowAnswersConfirmPending = true
                            menuOpen = false
                        } else {
                            game.toggleShowIncorrect()
                            menuOpen = false
                        }
                    },
                    onConfirmYes: {
                        game.toggleShowIncorrect()
                        game.dailyShowAnswersConfirmPending = false
                        menuOpen = false
                    },
                    onConfirmNo: {
                        game.dailyShowAnswersConfirmPending = false
                    }
                )
                if let p = game.puzzle {
                    MenuSheetShareRow(
                        index: 5,
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(menuOpen)
    }

    /// Hidden player-facing unlock wired into the settings row's
    /// 3-second long-press: clears every lock on the current puzzle
    /// and opens every level tier in the zen picker. Shipped in
    /// Release so players who want to skip the grind can find it.
    private var settingsLongPressAction: (() -> Void)? {
        return {
            Haptics.solve()
            game.debugUnlockAllLocks()
            menuOpen = false
        }
    }
}

/// Share variant of the hamburger row — same slide-in-from-right +
/// label-fade animation pattern as `MenuSheetRow`. Pre-fetches a
/// short share URL by POSTing the puzzle JSON to `/api/share` when
/// the menu opens; the resulting `https://kroma.ianhandy.com/p/<slug>`
/// is what the `ShareLink` actually shares, so recipients see an
/// iMessage card titled "Kromatika puzzle (X/10)" instead of a
/// generic `.kroma` attachment.
///
/// Three render states:
///   1. Preparing (no URL yet, no tap — spinner shown).
///   2. URL ready — `ShareLink(item: URL)` with `SharePreview` for the
///      title + preview image.
///   3. API failed / offline — `ShareLink(item: KromaPuzzleFile)`
///      fallback so sharing never hard-breaks; recipient gets the
///      `.kroma` attachment + the app's UTI handler picks it up.
private struct MenuSheetShareRow: View {
    let index: Int
    let isOpen: Bool
    let puzzle: Puzzle

    @State private var iconArrived = false
    @State private var labelVisible = false
    @State private var shareURL: URL? = nil
    @State private var preparing: Bool = false
    @State private var apiFailed: Bool = false
    @State private var prepareTask: Task<Void, Never>? = nil

    var body: some View {
        let json = (try? CreatorCodec.encodePuzzle(puzzle)) ?? ""
        let file = KromaPuzzleFile(json: json, difficulty: puzzle.difficulty)
        let previewImage = PuzzlePreviewRenderer.render(puzzle)
            ?? Image(systemName: "paintpalette.fill")
        let title = "Kromatika puzzle (\(puzzle.difficulty)/10)"
        let preview = SharePreview(title, image: previewImage)

        Group {
            if let url = shareURL {
                ShareLink(item: url, subject: Text(title), preview: preview) {
                    shareLabel(waiting: false)
                }
            } else if preparing {
                // Non-tappable while the slug is being minted — taps
                // during the brief prep window otherwise fall through
                // to the file-share fallback, which is the bug we're
                // fixing.
                shareLabel(waiting: true)
            } else if apiFailed {
                // Offline / API unreachable — degrade to file share
                // so the user can still send the puzzle, just without
                // the iMessage card.
                ShareLink(item: file, subject: Text(title), preview: preview) {
                    shareLabel(waiting: false)
                }
            } else {
                // Initial state before the menu has ever opened.
                shareLabel(waiting: false)
            }
        }
        .onChange(of: isOpen) { _, open in
            if open {
                startPrepare(json: json)
                withAnimation(.spring(response: 0.52, dampingFraction: 0.84)
                    .delay(Double(index) * 0.09)) {
                    iconArrived = true
                }
                withAnimation(.easeIn(duration: 0.45)
                    .delay(Double(index) * 0.09 + 0.40)) {
                    labelVisible = true
                }
            } else {
                prepareTask?.cancel()
                prepareTask = nil
                preparing = false
                shareURL = nil
                apiFailed = false
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

    private func startPrepare(json: String) {
        prepareTask?.cancel()
        shareURL = nil
        apiFailed = false
        preparing = true
        prepareTask = Task { @MainActor in
            let url = await Self.requestShareURL(json: json)
            guard !Task.isCancelled else { return }
            if let url {
                shareURL = url
            } else {
                apiFailed = true
            }
            preparing = false
            prepareTask = nil
        }
    }

    private static func requestShareURL(json: String) async -> URL? {
        guard let endpoint = URL(string: "https://kroma.ianhandy.com/api/share") else {
            return nil
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        guard let body = try? JSONSerialization.data(withJSONObject: ["json": json]) else {
            return nil
        }
        request.httpBody = body
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(ShareSaveResponse.self, from: data)
            return URL(string: decoded.url)
        } catch {
            return nil
        }
    }

    /// Share row label.
    @ViewBuilder
    private func shareLabel(waiting: Bool) -> some View {
        HStack(spacing: 14) {
            Text(waiting ? "preparing…" : "share")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(waiting ? 0.55 : 0.92))
                .opacity(labelVisible ? 1 : 0)
            ZStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(waiting ? 0.45 : 0.95))
                if waiting {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(Color.white.opacity(0.85))
                }
            }
            .frame(width: 46, height: 46)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
        }
        .offset(x: iconArrived ? 0 : 280)
    }
}

private struct ShareSaveResponse: Decodable {
    let slug: String
    let url: String
}

/// Show-incorrect hamburger row with inline confirmation support.
/// When the daily-mode "are you sure?" confirm flag is set on
/// GameState, the row morphs into a small inline prompt
/// (styled like the main-menu challenge resume) so the player
/// can confirm without a full-screen modal.
private struct ShowIncorrectMenuRow: View {
    @Bindable var game: GameState
    let index: Int
    let isOpen: Bool
    let disabled: Bool
    let onTapPrimary: () -> Void
    let onConfirmYes: () -> Void
    let onConfirmNo: () -> Void

    var body: some View {
        if game.dailyShowAnswersConfirmPending {
            HStack(spacing: 12) {
                Text("are you sure?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.80))
                Button {
                    onConfirmYes()
                } label: {
                    Text("yes")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.55))
                }
                .buttonStyle(.plain)
                Button {
                    onConfirmNo()
                } label: {
                    Text("no")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.92, green: 0.48, blue: 0.48))
                }
                .buttonStyle(.plain)
                MenuSheetRow(
                    icon: "exclamationmark.triangle",
                    label: "show incorrect",
                    index: index,
                    isOpen: isOpen,
                    disabled: false,
                    action: {}
                )
            }
            .padding(.vertical, 6)
            .transition(.opacity)
        } else {
            MenuSheetRow(
                icon: game.showIncorrect
                    ? "exclamationmark.triangle.fill"
                    : "exclamationmark.triangle",
                label: game.showIncorrect
                    ? "hide incorrect"
                    : "show incorrect",
                index: index,
                isOpen: isOpen,
                disabled: disabled,
                action: onTapPrimary
            )
        }
    }
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
    /// When true, the row dims and ignores taps — used when the
    /// row's action isn't meaningful in the current game state
    /// (e.g. show-incorrect while solved or in challenge mode).
    /// Keeps the row in place so the layout doesn't jump.
    var disabled: Bool = false
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
            if disabled { return }
            if longPressConsumed { longPressConsumed = false; return }
            action()
        }) {
            HStack(spacing: 14) {
                Text(label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(disabled ? 0.35 : 0.92))
                    .opacity(labelVisible ? 1 : 0)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(disabled ? 0.40 : 0.95))
                    .frame(width: 46, height: 46)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(disabled ? 0.30 : 0.55))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(disabled ? 0.12 : 0.28), lineWidth: 1)
                    )
            }
            .offset(x: iconArrived ? 0 : 280)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
