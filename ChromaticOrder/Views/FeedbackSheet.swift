//  Feedback sheet. Two 1-10 sliders + optional notes, plus an auto-
//  attached diagnostic block with the generator's per-puzzle metrics.
//
//  Primary action: Send — POSTs to the Google Form (see
//  FeedbackSubmitter) so reports land in the linked Sheet the dev
//  can browse. Secondary action: Copy, as a fallback for anyone
//  behind a restrictive network.

import SwiftUI
import UIKit

struct FeedbackSheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    @State private var difficultyRating: Double = 5
    @State private var qualityRating: Double = 5
    @State private var note: String = ""

    // Submission state machine. idle → sending → sent | failed.
    // On .sent we auto-dismiss after a beat so the player doesn't
    // feel stuck. .failed keeps the sheet open with the error + Copy
    // available for manual delivery.
    private enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }
    @State private var sendState: SendState = .idle
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
                        Text("Auto-attached")
                            .font(.system(size: 13, weight: .bold))
                        Text("Sent with your report so the dev can correlate your ratings with the puzzle's generator metrics. No personal data.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(diagnosticPreview)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 8))
                    }

                    sendRow
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

    // MARK: - Send row

    @ViewBuilder
    private var sendRow: some View {
        VStack(spacing: 10) {
            Button {
                Task { await send() }
            } label: {
                Group {
                    switch sendState {
                    case .idle, .failed:
                        Label("Send Feedback", systemImage: "paperplane.fill")
                    case .sending:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Sending…")
                        }
                    case .sent:
                        Label("Sent", systemImage: "checkmark")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sendState == .sending || sendState == .sent)

            if case .failed(let msg) = sendState {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.85, green: 0.2, blue: 0.2))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = clipboardPayload
                    copyConfirmed = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label(
                        copyConfirmed ? "Copied" : "Copy as text",
                        systemImage: copyConfirmed ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(.bordered)

                ShareLink(item: clipboardPayload) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func send() async {
        sendState = .sending
        let payload = buildPayload()
        do {
            try await FeedbackSubmitter.submit(payload)
            sendState = .sent
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)  // 0.9s
            dismiss()
        } catch {
            sendState = .failed(error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    // MARK: - Payload + preview

    private func buildPayload() -> FeedbackPayload {
        let version = appVersionString
        let dev = deviceString
        let p = game.puzzle
        return FeedbackPayload(
            difficulty: Int(difficultyRating),
            quality: Int(qualityRating),
            notes: note.trimmingCharacters(in: .whitespacesAndNewlines),
            appVersion: version,
            device: dev,
            level: game.level,
            mode: game.mode.rawValue,
            generatorDifficulty: p?.difficulty ?? 0,
            channels: p.map { $0.activeChannels.map { ch in ch.rawValue.uppercased() }.joined(separator: "+") } ?? "",
            primaryChannel: p?.primaryChannel.rawValue.uppercased() ?? "",
            grid: p.map { "\($0.gridW)x\($0.gridH)" } ?? "",
            gradientCount: p?.gradients.count ?? 0,
            bankSize: p?.initialBankCount ?? 0,
            pairProx: p?.pairProx ?? 0,
            extrapProx: p?.extrapProx ?? 0,
            interDist: p?.interDist ?? 0,
            gradientMetrics: perGradientMetrics(p),
            reduceMotion: game.reduceMotion,
            completed: game.solved,
            timeSpentSec: game.timeSpentSec,
            mistakes: game.mistakeCount,
            cbMode: game.cbMode.rawValue
        )
    }

    /// Per-gradient in-line similarity data. Multi-line so it lands
    /// in the Sheet as one text column the dev can eyeball.
    private func perGradientMetrics(_ p: Puzzle?) -> String {
        guard let p else { return "" }
        var lines: [String] = []
        for g in p.gradients {
            var totalStep = 0.0, stepN = 0
            var minStep = Double.infinity, maxStep = 0.0
            for i in 1..<g.colors.count {
                let d = OK.dist(g.colors[i - 1], g.colors[i])
                totalStep += d; stepN += 1
                if d < minStep { minStep = d }
                if d > maxStep { maxStep = d }
            }
            let avg = stepN > 0 ? totalStep / Double(stepN) : 0
            if minStep == .infinity { minStep = 0 }
            lines.append(String(
                format: "%@ len=%d avg=%.2f min=%.2f max=%.2f",
                g.dir.rawValue, g.len, avg, minStep, maxStep
            ))
        }
        return lines.joined(separator: "\n")
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var deviceString: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    /// Text version of the payload for the Copy/Share fallback —
    /// same fields the form gets, readable at a glance.
    private var clipboardPayload: String {
        let p = buildPayload()
        var out = """
        — ratings —
        difficulty: \(p.difficulty)/10
        quality: \(p.quality)/10
        """
        if !p.notes.isEmpty {
            out += "\nnotes: \(p.notes)"
        }
        out += """


        — app —
        version: \(p.appVersion)
        device: \(p.device)
        level: \(p.level)
        mode: \(p.mode)
        reduceMotion: \(p.reduceMotion)
        cbMode: \(p.cbMode)

        — session —
        completed: \(p.completed)
        timeSpent: \(p.timeSpentSec)s
        mistakes: \(p.mistakes)
        """
        if game.puzzle != nil {
            out += """


            — puzzle —
            difficulty(gen): \(p.generatorDifficulty)/10
            channels: \(p.channels) (primary: \(p.primaryChannel))
            grid: \(p.grid)
            gradients: \(p.gradientCount)
            bank: \(p.bankSize)
            pairProx: \(String(format: "%.2f", p.pairProx))
            extrapProx: \(String(format: "%.2f", p.extrapProx))
            interDist: \(String(format: "%.1f", p.interDist))

            \(p.gradientMetrics)
            """
        }
        return out
    }

    /// Shorter preview used in the sheet's auto-attached block so
    /// the player sees exactly what's being submitted.
    private var diagnosticPreview: String { clipboardPayload }

    // MARK: - UI bits

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
                    Text(title).font(.system(size: 13, weight: .bold))
                    Text(help).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(minWidth: 40)
                    .monospacedDigit()
            }
            Slider(value: value, in: 1...10, step: 1).tint(tint)
        }
    }
}
