//  Floating bottom-right widget — one-tap per-level feedback.
//  Green up arrow / red down arrow for like / dislike. After a tap,
//  the widget pivots into a "Want to leave feedback?" prompt so
//  players who care enough to rate can also go deep, without
//  blocking players who just want to move on to the next level.
//
//  State lifecycle:
//    unrated            → both arrows available, POST on tap
//    rated (just now)   → arrow row replaced by Yes / No prompt
//    feedback dismissed → quiet pill showing the picked arrow only
//    new level          → state resets (game.liked = nil from startLevel)
//
//  The full FeedbackSheet in the hamburger menu is still the
//  destination — this widget exists to surface that path right at
//  the moment the player has a reaction to share.

import SwiftUI

struct LikeFeedbackWidget: View {
    @Bindable var game: GameState
    /// Opens the full FeedbackSheet. ContentView owns the binding;
    /// we just flip it when the player taps Yes on the prompt.
    @Binding var feedbackOpen: Bool
    /// Outer height — caller matches this to the "next level" button's
    /// capsule so the two side-by-side affordances line up on one
    /// baseline.
    var height: CGFloat = 52

    /// Whether the "Want to leave feedback?" prompt is currently
    /// showing. Flipped true immediately after tap(liked:); flipped
    /// false on Yes / No dismissal. Not persisted — every level starts
    /// back at the arrow row.
    @State private var promptVisible: Bool = false

    private let likeGreen  = Color(red: 0.36, green: 0.78, blue: 0.45)
    private let dislikeRed = Color(red: 0.92, green: 0.42, blue: 0.42)

    var body: some View {
        Group {
            if promptVisible {
                feedbackPromptRow
            } else {
                ratingRow
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: game.liked)
        .animation(.easeOut(duration: 0.2), value: promptVisible)
        .onChange(of: game.liked) { _, newValue in
            // Level advanced (startLevel sets liked = nil) — clear
            // any lingering prompt so the next level starts fresh on
            // the arrow row.
            if newValue == nil { promptVisible = false }
        }
    }

    @ViewBuilder
    private var ratingRow: some View {
        HStack(spacing: 8) {
            Text(Strings.LikeFeedback.prompt)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.white.opacity(0.55))

            HStack(spacing: 10) {
                // Green up / red down arrows. Filled variants are
                // unambiguous at small sizes on both light + dark
                // sims.
                Button {
                    tap(liked: true)
                } label: {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(likeGreen)
                        .opacity(opacity(for: true))
                }
                .buttonStyle(.plain)
                .disabled(game.liked != nil)

                Button {
                    tap(liked: false)
                } label: {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(dislikeRed)
                        .opacity(opacity(for: false))
                }
                .buttonStyle(.plain)
                .disabled(game.liked != nil)
            }
        }
    }

    @ViewBuilder
    private var feedbackPromptRow: some View {
        HStack(spacing: 10) {
            Text("Leave feedback?")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Button("Yes") {
                promptVisible = false
                feedbackOpen = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(likeGreen)

            Button("No") {
                promptVisible = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color.white.opacity(0.4))
        }
    }

    private func tap(liked value: Bool) {
        guard game.liked == nil else { return }
        game.liked = value
        // Pivot the row to the "Want to leave feedback?" prompt so
        // the player can opt into the full FeedbackSheet without the
        // hamburger-menu detour. Reset happens in startLevel along
        // with `game.liked = nil`.
        promptVisible = true
        // One JSON blob carries everything: puzzle structure, per-cell
        // locks, difficulty, session context (level / mode / cbMode).
        // Everything else is derivable from it, so no need for a
        // fistful of flat form columns.
        let json: String = {
            guard let p = game.puzzle else { return "" }
            return (try? CreatorCodec.encodePuzzleWithSession(
                p,
                level: game.level,
                mode: game.mode.rawValue,
                cbMode: game.cbMode.rawValue
            )) ?? ""
        }()
        let payload = LikePayload(liked: value, json: json)
        Task.detached(priority: .utility) {
            await LikeFeedbackSubmitter.submit(payload)
        }
        // Community pool wiring:
        //   • Like → append to local liked pool AND POST to the
        //     server community pool (decremented only by matching
        //     dislikes).
        //   • Dislike → POST to the server dislike endpoint, which
        //     decrements this puzzle's community like_count and
        //     logs the dislike for generator-tuning analytics.
        // Nothing local for dislikes — they're server-only.
        if !json.isEmpty {
            if value, let p = game.puzzle {
                LikedPuzzleStore.like(puzzle: p, puzzleJSON: json, level: game.level)
            } else if !value {
                let sig = game.puzzle.map { PuzzleShape.signature(of: $0.gradients) }
                LikedPuzzleStore.dislike(
                    puzzleJSON: json,
                    shapeSignature: sig,
                    level: game.level
                )
            }
        }
    }

    /// Dim the button that DIDN'T get tapped; leave the chosen one
    /// at full opacity so the player sees their pick hold.
    private func opacity(for value: Bool) -> Double {
        guard let liked = game.liked else { return 1.0 }
        return liked == value ? 1.0 : 0.22
    }
}
