//  Floating bottom-right widget — one-tap per-level feedback.
//  "good level?" text with 🙂 / 🙁 buttons next to it.
//
//  State lifecycle:
//    unrated   → both buttons available, POST on tap
//    rated     → picked button stays, the other dims + disables
//    new level → state resets (game.liked = nil from startLevel)
//
//  Deliberately lightweight — the full feedback sheet in the menu
//  captures the rich per-level data (sliders + puzzle metrics). This
//  widget is the "leave a quick reaction without opening a menu" path.

import SwiftUI

struct LikeFeedbackWidget: View {
    @Bindable var game: GameState
    /// Outer height — caller matches this to the "next level" button's
    /// capsule so the two side-by-side affordances line up on one
    /// baseline. Default keeps the widget self-contained when used in
    /// isolation.
    var height: CGFloat = 52

    var body: some View {
        HStack(spacing: 8) {
            Text(Strings.LikeFeedback.prompt)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.white.opacity(0.55))

            HStack(spacing: 10) {
                // SF Symbols render reliably on simulator + device;
                // literal 🙂 / 🙁 glyphs drop to ? on some sim fonts.
                // Tint carries the smiley/frowny semantics via color
                // (green like, red dislike) without relying on emoji.
                Button {
                    tap(liked: true)
                } label: {
                    Image(systemName: "face.smiling.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.36, green: 0.78, blue: 0.45))
                        .opacity(opacity(for: true))
                }
                .buttonStyle(.plain)
                .disabled(game.liked != nil)

                Button {
                    tap(liked: false)
                } label: {
                    Image(systemName: "face.dashed.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.92, green: 0.42, blue: 0.42))
                        .opacity(opacity(for: false))
                }
                .buttonStyle(.plain)
                .disabled(game.liked != nil)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: game.liked)
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
