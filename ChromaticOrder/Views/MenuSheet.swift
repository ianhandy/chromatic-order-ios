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
                    isOpen: menuOpen
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
                MenuSheetRow(
                    icon: game.showIncorrect
                        ? "exclamationmark.triangle.fill"
                        : "exclamationmark.triangle",
                    label: game.showIncorrect
                        ? "hide incorrect"
                        : "show incorrect",
                    index: 3,
                    isOpen: menuOpen && canShowIncorrect
                ) {
                    game.toggleShowIncorrect()
                    menuOpen = false
                }
                if let p = game.puzzle {
                    MenuSheetShareRow(
                        index: 4,
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
}

/// Share variant of the hamburger row — same slide-in-from-right +
/// label-fade animation pattern as `MenuSheetRow`, but wraps a
/// SwiftUI `ShareLink` so tapping opens the system share sheet with
/// the current puzzle as a `.kroma` attachment plus a `kroma://`
/// deep link. ShareLink can't sit inside a regular Button so it
/// gets its own row type rather than threading through MenuSheetRow.
private struct MenuSheetShareRow: View {
    let index: Int
    let isOpen: Bool
    let puzzle: Puzzle

    @State private var iconArrived = false
    @State private var labelVisible = false

    var body: some View {
        let json = (try? CreatorCodec.encodePuzzle(puzzle)) ?? ""
        let file = KromaPuzzleFile(json: json, difficulty: puzzle.difficulty)
        let shareURL = URL(string:
            "kroma://play?data=\(ChromaticOrderApp.encodeBase64URL(Data(json.utf8)))"
        ) ?? URL(string: "https://kromatika.app")!

        ShareLink(
            item: file,
            subject: Text("A Kromatika puzzle"),
            message: Text("difficulty \(puzzle.difficulty)/10 — tap to play: \(shareURL)"),
            preview: SharePreview(
                "Kromatika puzzle (\(puzzle.difficulty)/10)",
                image: Image(systemName: "paintpalette.fill")
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
}

private struct MenuSheetRow: View {
    let icon: String
    let label: String
    let index: Int
    let isOpen: Bool
    let action: () -> Void

    /// True once the icon has (animated) slid to its resting x=0 spot.
    /// Drives the icon's offset. Starts false so cold launch = closed
    /// = offscreen. Flipped by onChange when `isOpen` toggles.
    @State private var iconArrived = false
    /// True once the label has (animated) faded to opacity 1. Always
    /// trails `iconArrived` on open so the label reveals after the
    /// icon has settled.
    @State private var labelVisible = false

    var body: some View {
        Button(action: action) {
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
