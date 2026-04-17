//  Floating bottom-right widget — one-tap per-level feedback.
//  "Did you like this level?" text with 🙂 / 🙁 buttons next to it.
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

    var body: some View {
        HStack(spacing: 8) {
            Text("Did you like this level?")
                .font(.system(size: 11, weight: .medium, design: .rounded))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: game.liked)
    }

    private func tap(liked value: Bool) {
        guard game.liked == nil else { return }
        game.liked = value
        // Snapshot everything on the main actor BEFORE handing off —
        // LikeFeedbackSubmitter.submit is detached and can't read
        // MainActor-isolated state. The puzzle JSON is the bulkiest
        // piece and the one that matters most for later replay.
        let payload = LikePayload(
            liked: value,
            level: game.level,
            generatorDifficulty: game.puzzle?.difficulty ?? 0,
            channels: game.puzzle.map { $0.activeChannels.map { $0.rawValue.uppercased() }.joined(separator: "+") } ?? "",
            primaryChannel: game.puzzle?.primaryChannel.rawValue.uppercased() ?? "",
            grid: game.puzzle.map { "\($0.gridW)x\($0.gridH)" } ?? "",
            mode: game.mode.rawValue,
            cbMode: game.cbMode.rawValue,
            puzzleJSON: (try? game.puzzle.flatMap { try CreatorCodec.encodePuzzle($0) }) ?? ""
        )
        Task.detached(priority: .utility) {
            await LikeFeedbackSubmitter.submit(payload)
        }
    }

    /// Dim the button that DIDN'T get tapped; leave the chosen one
    /// at full opacity so the player sees their pick hold.
    private func opacity(for value: Bool) -> Double {
        guard let liked = game.liked else { return 1.0 }
        return liked == value ? 1.0 : 0.22
    }
}
