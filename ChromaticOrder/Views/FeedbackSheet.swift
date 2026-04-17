//  Dev-oriented feedback sheet.
//
//  Primary input is two 1-10 sliders (difficulty + quality) so each
//  report lets me correlate the player's perceived difficulty / polish
//  with the generator's metrics (pairProx, extrapProx, per-gradient
//  stepΔE, etc., appended as a diagnostic block below).
//
//  Notes are optional — used for anything the sliders don't capture.
//  Copy to Clipboard is the expected send mechanism; ShareLink is a
//  fallback for Mail / Messages.

import SwiftUI
import UIKit

struct FeedbackSheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    // Sliders default to the middle of the scale (5) — an explicit
    // "no rating" state would force the player through a three-state
    // selector that reads as fussier than this screen deserves.
    @State private var difficultyRating: Double = 5
    @State private var qualityRating: Double = 5
    @State private var note: String = ""
    @State private var copyConfirmed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ratingRow(
                        title: "Difficulty",
                        help: "1 = trivial, 10 = brutal",
                        value: $difficultyRating,
                        tint: Color(red: 0.85, green: 0.47, blue: 0))
                    ratingRow(
                        title: "Quality",
                        help: "1 = bad puzzle, 10 = great puzzle",
                        value: $qualityRating,
                        tint: Color(red: 0.16, green: 0.62, blue: 0.31))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.system(size: 13, weight: .bold))
                        Text("Anything the sliders don't capture")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $note)
                            .font(.system(size: 14))
                            .padding(6)
                            .frame(minHeight: 120)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto-attached diagnostic")
                            .font(.system(size: 13, weight: .bold))
                        Text("Included so the dev can correlate your ratings with the generator's output. No personal data.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(diagnostic)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = payload
                            copyConfirmed = true
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: {
                            Label(
                                copyConfirmed ? "Copied" : "Copy to Clipboard",
                                systemImage: copyConfirmed ? "checkmark" : "doc.on.doc"
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)

                        ShareLink(item: payload) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
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

    // Slider row factored out so the two ratings look and behave
    // identically — large readout on the right, label+help on the left.
    @ViewBuilder
    private func ratingRow(
        title: String,
        help: String,
        value: Binding<Double>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                    Text(help)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(minWidth: 40)
                    .monospacedDigit()
            }
            Slider(value: value, in: 1...10, step: 1)
                .tint(tint)
        }
    }

    // MARK: - Diagnostic + payload

    private var diagnostic: String {
        let versionInfo = Bundle.main.infoDictionary.flatMap { info -> String? in
            let short = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            return "\(short) (\(build))"
        } ?? "unknown"

        var out = """
        — ratings —
        difficulty: \(Int(difficultyRating))/10
        quality: \(Int(qualityRating))/10

        — diagnostic —
        app: ChromaticOrder \(versionInfo)
        level: \(game.level)
        mode: \(game.mode.rawValue)
        checks: \(game.checks)
        score: \(game.score)
        reduceMotion: \(game.reduceMotion)
        device: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """

        if let p = game.puzzle {
            let activeChannels = p.activeChannels
                .map { $0.rawValue.uppercased() }
                .joined(separator: "+")
            out += "\n\n— puzzle —\n"
            out += "difficulty(gen): \(p.difficulty)/10\n"
            out += "channels: \(activeChannels) (primary: \(p.primaryChannel.rawValue.uppercased()))\n"
            out += "grid: \(p.gridW)x\(p.gridH)\n"
            out += "gradients: \(p.gradients.count)\n"
            out += "bankInitial: \(p.initialBankCount)\n"
            out += String(format: "pairProx: %.2f  (close cells across grads, lower is easier)\n", p.pairProx)
            out += String(format: "extrapProx: %.2f  (on-extended-line score)\n", p.extrapProx)
            out += String(format: "interDist: %.1f  (min line-to-polyline ΔE between grads)\n", p.interDist)

            out += "\ngrads:\n"
            for g in p.gradients {
                var totalStep = 0.0, stepN = 0
                var minStep = Double.infinity, maxStep = 0.0
                for i in 1..<g.colors.count {
                    let d = OK.dist(g.colors[i - 1], g.colors[i])
                    totalStep += d
                    stepN += 1
                    if d < minStep { minStep = d }
                    if d > maxStep { maxStep = d }
                }
                let avgStep = stepN > 0 ? totalStep / Double(stepN) : 0
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
        return body.isEmpty ? diagnostic : body + "\n\n" + diagnostic
    }
}
