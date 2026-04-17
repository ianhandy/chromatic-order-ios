//  Feedback sheet. Lets the player write notes + copy a bundled
//  payload (their message plus an auto-generated diagnostic block
//  with app build, current level, mode, score, reduce-motion flag)
//  to the clipboard. Also offers a Share action for Mail / iMessage.

import SwiftUI
import UIKit

struct FeedbackSheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""
    @State private var copyConfirmed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell us what worked, what didn't, or what you'd like to see. The block below is appended automatically — it only contains app + progress info (no personal data).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                TextEditor(text: $note)
                    .font(.system(size: 14))
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("Your feedback…")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 24)
                                .padding(.top, 18)
                                .allowsHitTesting(false)
                        }
                    }

                // Diagnostic preview — read-only, identical to what
                // gets appended on copy. Shows the player exactly what
                // they'll be pasting, which is the right way to handle
                // "we auto-attach this data."
                ScrollView {
                    Text(diagnostic)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 120)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = payload
                        copyConfirmed = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label(copyConfirmed ? "Copied" : "Copy to Clipboard",
                              systemImage: copyConfirmed ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: payload) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(height: 42)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var diagnostic: String {
        let versionInfo = Bundle.main.infoDictionary.flatMap { info -> String? in
            let short = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            return "\(short) (\(build))"
        } ?? "unknown"
        return """
        — diagnostic —
        app: ChromaticOrder \(versionInfo)
        level: \(game.level)
        mode: \(game.mode.rawValue)
        checks: \(game.checks)
        score: \(game.score)
        reduceMotion: \(game.reduceMotion)
        device: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """
    }

    private var payload: String {
        let body = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return diagnostic }
        return body + "\n\n" + diagnostic
    }
}
