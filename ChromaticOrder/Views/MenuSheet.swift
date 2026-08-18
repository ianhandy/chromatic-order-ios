//  The in-game menu. A panel anchored under the top bar's menu button,
//  ordered the way iOS orders a menu: the actions that touch this puzzle
//  first, then the app-level destinations, then the way out.
//
//  It used to be a set of unbacked rows that slid in from the right edge
//  on a per-index stagger, each label fading in 400ms after its icon.
//  Two problems that cost more than the choreography was worth: with no
//  surface behind them the labels landed directly on the puzzle (the
//  "share" row was routinely unreadable over a swatch), and the stagger
//  indices had a gap in them, so the list arrived with a dead beat in the
//  middle. A panel with one brief anchored transition says the same thing
//  — "this came from that button" — and stays legible over any board.
//
//  Always mounted so the dismissal transition can play out; hit-testing
//  is gated on `menuOpen` so a closed menu never eats taps on the game.

import SwiftUI

struct MenuSheet: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool
    @Binding var creatorOpen: Bool
    @Binding var feedbackOpen: Bool
    @Binding var accessibilityOpen: Bool
    @Binding var started: Bool
    @Environment(Transitioner.self) private var transitioner
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        // "Show incorrect" is available in zen (free) and daily (allowed,
        // but using it disqualifies the leaderboard submission — handled
        // in GameState.handleNext). Challenge hides it: there, revealing
        // incorrect cells is what Check does, at the cost of a heart.
        // Nothing to check once the puzzle is already solved.
        let canShowIncorrect = game.mode != .challenge && !game.solved
        let canHint = game.puzzle != nil && !game.generating && !game.solved

        ZStack(alignment: .topTrailing) {
            if menuOpen {
                // Transparent full-screen catcher. Closes the menu
                // without firing any game action underneath it.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { menuOpen = false }
                    .accessibilityLabel("close menu")
                    .accessibilityAddTraits(.isButton)

                VStack(alignment: .leading, spacing: 0) {
                    MenuPanelRow(icon: "lightbulb",
                                 label: "hint",
                                 disabled: !canHint) {
                        if game.mode == .daily && !game.usedHintThisLevel {
                            game.dailyHintConfirmPending = true
                        } else {
                            game.requestHint()
                        }
                        menuOpen = false
                    }

                    MenuPanelRow(icon: game.showIncorrect
                                    ? "eye.slash"
                                    : "exclamationmark.triangle",
                                 label: game.showIncorrect
                                    ? "hide incorrect"
                                    : "show incorrect",
                                 disabled: !canShowIncorrect,
                                 action: toggleShowIncorrect)

                    if let puzzle = game.puzzle {
                        MenuPanelDivider()
                        MenuShareRow(puzzle: puzzle, isOpen: menuOpen)
                    }

                    MenuPanelDivider()
                    MenuPanelRow(icon: "gearshape",
                                 label: Strings.Menu.settings,
                                 // A 3-second hold clears every lock on the
                                 // current puzzle. Deliberately undiscoverable
                                 // rather than hidden: players who want to skip
                                 // the grind can find it, nobody hits it by
                                 // accident.
                                 onLongPress: {
                                     Haptics.solve()
                                     game.debugUnlockAllLocks()
                                     menuOpen = false
                                 }) {
                        menuOpen = false
                        accessibilityOpen = true
                    }
                    MenuPanelRow(icon: "envelope",
                                 label: "feedback") {
                        menuOpen = false
                        feedbackOpen = true
                    }

                    MenuPanelDivider()
                    exitRow
                }
                .frame(maxWidth: 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .kromaSurface(.panel,
                              in: RoundedRectangle(cornerRadius: Kroma.Radius.panel,
                                                   style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
                .padding(.trailing, Kroma.Space.l)
                .padding(.top, 54)
                // Grows out of the button that opened it. Reduce Motion
                // gets the same state change as a plain fade.
                .transition(shouldReduceMotion
                            ? .opacity
                            : .scale(scale: 0.9, anchor: .topTrailing)
                                .combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .kromaAnimation(shouldReduceMotion ? nil : .snappy(duration: 0.22),
                        value: menuOpen)
        .allowsHitTesting(menuOpen)
    }

    private var shouldReduceMotion: Bool {
        systemReduceMotion || game.reduceMotion
    }

    /// Leaving the game returns the player to wherever they entered
    /// from, so the label names that place rather than saying "back".
    @ViewBuilder
    private var exitRow: some View {
        if game.cameFromGallery {
            MenuPanelRow(icon: "square.grid.2x2", label: Strings.Menu.gallery) {
                menuOpen = false
                game.parkInProgressSession()
                game.openGalleryOnMenuAppear = true
                transitioner.fade { started = false }
            }
        } else if game.campaignIndex != nil {
            MenuPanelRow(icon: "list.number", label: Strings.Menu.campaign) {
                menuOpen = false
                game.parkInProgressSession()
                game.openCampaignOnMenuAppear = true
                transitioner.fade { started = false }
            }
        } else {
            MenuPanelRow(icon: "house", label: "home") {
                menuOpen = false
                game.parkInProgressSession()
                transitioner.fade { started = false }
            }
        }
    }

    private func toggleShowIncorrect() {
        // In daily, enabling show-incorrect voids leaderboard
        // eligibility — close the menu and pop the confirmation on the
        // game screen, where the full "disables leaderboards" copy gets
        // a darkened backdrop instead of being tucked into a menu row.
        if game.mode == .daily && !game.showIncorrect {
            game.dailyShowAnswersConfirmPending = true
        } else {
            game.toggleShowIncorrect()
        }
        menuOpen = false
    }
}

// MARK: - Panel parts

/// One row of the in-game menu. Laid out like a system menu row: label
/// leading, glyph trailing, whole row tappable at no less than 44pt tall.
private struct MenuPanelRow: View {
    let icon: String
    let label: String
    var disabled: Bool = false
    var onLongPress: (() -> Void)? = nil
    let action: () -> Void

    /// Latched when a long-press fires so the tap-on-release handler
    /// bows out — `simultaneousGesture` otherwise fires both.
    @State private var longPressConsumed = false

    var body: some View {
        Button {
            if longPressConsumed { longPressConsumed = false; return }
            action()
        } label: {
            HStack(spacing: Kroma.Space.m) {
                Text(label)
                    .font(Kroma.font(.body, .medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Kroma.Space.s)
                Image(systemName: icon)
                    .font(.body)
                    .imageScale(.medium)
                    .frame(width: 22)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Kroma.Space.l)
            .padding(.vertical, Kroma.Space.m)
            .frame(minHeight: Kroma.Metrics.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.kromaControl)
        .disabled(disabled)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 3.0).onEnded { _ in
                guard let onLongPress else { return }
                longPressConsumed = true
                onLongPress()
            }
        )
    }
}

private struct MenuPanelDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.white.opacity(0.12))
            .padding(.horizontal, Kroma.Space.m)
    }
}

/// Share row. Pre-fetches a short URL by POSTing the puzzle JSON to
/// `/api/share` when the menu opens, so the recipient sees an iMessage
/// card titled "Kromatika puzzle (X/10)" rather than a bare `.kroma`
/// attachment.
///
/// Three states: preparing (not yet tappable, so a tap during the prep
/// window can't fall through to the file fallback), URL ready, and
/// API-failed — which degrades to sharing the file so sharing never
/// hard-breaks offline.
private struct MenuShareRow: View {
    let puzzle: Puzzle
    let isOpen: Bool

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
                    label(waiting: false)
                }
                .buttonStyle(.kromaControl)
            } else if preparing {
                label(waiting: true)
                    .accessibilityLabel("share")
                    .accessibilityValue("preparing")
            } else if apiFailed {
                ShareLink(item: file, subject: Text(title), preview: preview) {
                    label(waiting: false)
                }
                .buttonStyle(.kromaControl)
            } else {
                ShareLink(item: file, subject: Text(title), preview: preview) {
                    label(waiting: false)
                }
                .buttonStyle(.kromaControl)
            }
        }
        .onChange(of: isOpen) { _, open in
            if open {
                startPrepare(json: json)
            } else {
                prepareTask?.cancel()
                prepareTask = nil
                preparing = false
                shareURL = nil
                apiFailed = false
            }
        }
        .onAppear { if isOpen { startPrepare(json: json) } }
    }

    @ViewBuilder
    private func label(waiting: Bool) -> some View {
        HStack(spacing: Kroma.Space.m) {
            Text("share")
                .font(Kroma.font(.body, .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Kroma.Space.s)
            // The spinner replaces the glyph in the same 22pt slot, so
            // the row's text never shifts as the link is minted.
            ZStack {
                if waiting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .imageScale(.medium)
                }
            }
            .frame(width: 22)
        }
        .foregroundStyle(.white.opacity(waiting ? 0.5 : 1))
        .padding(.horizontal, Kroma.Space.l)
        .padding(.vertical, Kroma.Space.m)
        .frame(minHeight: Kroma.Metrics.minTarget)
        .contentShape(Rectangle())
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
}

private struct ShareSaveResponse: Decodable {
    let slug: String
    let url: String
}
