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

        var out = """
        — diagnostic —
        app: ChromaticOrder \(versionInfo)
        level: \(game.level)
        mode: \(game.mode.rawValue)
        checks: \(game.checks)
        score: \(game.score)
        reduceMotion: \(game.reduceMotion)
        device: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """

        // Append per-puzzle metrics when there's a live puzzle.
        // Generator-tuning data: difficulty, cross-gradient similarity
        // (pairProx), line-overlap similarity (extrapProx, interDist),
        // and per-gradient step magnitudes — lets me (the dev) see
        // "this puzzle rated X but step ΔE was tiny" on a given report.
        if let p = game.puzzle {
            let activeChannels = p.activeChannels
                .map { $0.rawValue.uppercased() }
                .joined(separator: "+")
            out += "\n\n— puzzle —\n"
            out += "difficulty: \(p.difficulty)/10\n"
            out += "channels: \(activeChannels) (primary: \(p.primaryChannel.rawValue.uppercased()))\n"
            out += "grid: \(p.gridW)x\(p.gridH)\n"
            out += "gradients: \(p.gradients.count)\n"
            out += "bankInitial: \(p.initialBankCount)\n"
            // Cross-gradient color similarity. High pairProx = close
            // colors across gradients (likely to confuse the player).
            out += String(format: "pairProx: %.2f  (close cells across grads, lower is easier)\n", p.pairProx)
            // "Would the plotted lines overlap?" — extrapProx scores
            // cells that sit on the extended line of another gradient.
            // High = ambiguous direction cues across gradients.
            out += String(format: "extrapProx: %.2f  (on-extended-line score)\n", p.extrapProx)
            out += String(format: "interDist: %.1f  (min line-to-polyline ΔE between grads)\n", p.interDist)

            // Per-gradient in-line similarity — the step ΔE the player
            // has to distinguish. Lower = harder to tell steps apart.
            out += "\ngrads:\n"
            for g in p.gradients {
                var totalStep = 0.0
                var stepN = 0
                for i in 1..<g.colors.count {
                    totalStep += OK.dist(g.colors[i - 1], g.colors[i])
                    stepN += 1
                }
                let avgStep = stepN > 0 ? totalStep / Double(stepN) : 0
                var minStep = Double.infinity, maxStep = 0.0
                for i in 1..<g.colors.count {
                    let d = OK.dist(g.colors[i - 1], g.colors[i])
                    if d < minStep { minStep = d }
                    if d > maxStep { maxStep = d }
                }
                if minStep == .infinity { minStep = 0 }
                out += String(
                    format: "  - %@ len=%d stepΔE avg=%.2f min=%.2f max=%.2f\n",
                    g.dir.rawValue, g.len, avgStep, minStep, maxStep
                )
            }
        }
        return out
    }

    private var payload: String {
        let body = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return diagnostic }
        return body + "\n\n" + diagnostic
    }
}
