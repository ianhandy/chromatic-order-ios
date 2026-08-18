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
    /// Retained for API compatibility with the ContentView call-site.
    /// The widget no longer opens the feedback sheet directly; the
    /// follow-up "Leave feedback?" prompt was removed per player
    /// feedback that it turned a one-tap rating into a two-step
    /// dialog. Players who want deeper feedback still have the
    /// hamburger-menu feedback row.
    @Binding var feedbackOpen: Bool
    /// Outer height — caller matches this to the "next level" button's
    /// capsule so the two side-by-side affordances line up on one
    /// baseline.
    var height: CGFloat = 52

    private let likeGreen  = Color(red: 0.36, green: 0.78, blue: 0.45)
    private let dislikeRed = Color(red: 0.92, green: 0.42, blue: 0.42)

    var body: some View {
        ratingRow
            .padding(.leading, Kroma.Space.m)
            .frame(minHeight: height)
            .kromaSurface(.control, in: Capsule())
            .kromaAnimation(.easeOut(duration: 0.2), value: game.liked)
    }

    @ViewBuilder
    private var ratingRow: some View {
        HStack(spacing: Kroma.Space.xs) {
            Text(Strings.LikeFeedback.prompt)
                .font(Kroma.font(.headline, .bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.white.opacity(0.55))
                .accessibilityHidden(true)

            // Up / down arrows. The glyphs stay small so the widget can
            // sit beside "next level", but each carries a full 44pt hit
            // region — they were 22pt targets before.
            Button {
                tap(liked: true)
            } label: {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(Kroma.font(.title3, .heavy))
                    .foregroundStyle(likeGreen)
                    .opacity(opacity(for: true))
                    .kromaHitTarget()
            }
            .buttonStyle(.kromaControl)
            .disabled(game.liked != nil)
            .accessibilityLabel("good level")
            .accessibilityValue(game.liked == true ? "chosen" : "")

            Button {
                tap(liked: false)
            } label: {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(Kroma.font(.title3, .heavy))
                    .foregroundStyle(dislikeRed)
                    .opacity(opacity(for: false))
                    .kromaHitTarget()
            }
            .buttonStyle(.kromaControl)
            .disabled(game.liked != nil)
            .accessibilityLabel("bad level")
            .accessibilityValue(game.liked == false ? "chosen" : "")
        }
    }

    private func tap(liked value: Bool) {
        guard game.liked == nil else { return }
        game.liked = value
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
