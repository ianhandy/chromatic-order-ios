import SwiftUI

struct EnjoymentPromptView: View {
    @Environment(PlayerEngagementStore.self) private var engagement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: Stage = .question
    @State private var responseTask: Task<Void, Never>?

    private enum Stage {
        case question
        case positive
        case negative
        case acknowledging
        case garbled
        case kidding
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch stage {
            case .positive:
                responseMark(text: Strings.EnjoymentPrompt.good, brokenHeart: false)
            case .negative:
                responseMark(text: Strings.EnjoymentPrompt.sorry, brokenHeart: true)
            case .acknowledging:
                Text(Strings.EnjoymentPrompt.okay)
                    .font(Kroma.font(.largeTitle, .heavy))
                    .foregroundStyle(.white)
                    .transition(.opacity)
            case .question, .garbled, .kidding:
                questionContent(garbled: stage == .garbled)
                    .overlay {
                        if stage == .kidding {
                            Text(Strings.EnjoymentPrompt.justKidding)
                                .font(Kroma.font(.title2, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, Kroma.Space.xl)
                                .padding(.vertical, Kroma.Space.l)
                                .background(.black, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.30), lineWidth: 1))
                                .shadow(color: .white.opacity(0.18), radius: 18)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: stage)
        .accessibilityAddTraits(.isModal)
        .onDisappear {
            responseTask?.cancel()
            responseTask = nil
        }
    }

    private func questionContent(garbled: Bool) -> some View {
        VStack(spacing: Kroma.Space.xxl) {
            Spacer()

            Text(display(Strings.EnjoymentPrompt.question, garbled: garbled))
                .font(Kroma.font(.largeTitle, .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Kroma.Space.m) {
                promptButton(display(Strings.EnjoymentPrompt.yes, garbled: garbled)) {
                    respond(.yes)
                }
                promptButton(display(Strings.EnjoymentPrompt.no, garbled: garbled)) {
                    respond(.no)
                }
                promptButton(display(Strings.EnjoymentPrompt.stopTalking, garbled: garbled)) {
                    respond(.stopTalking)
                }
            }
            .disabled(stage != .question)

            Spacer()
        }
        .padding(.horizontal, Kroma.Space.xxl)
        .padding(.vertical, Kroma.Space.xxl)
        // Under VoiceOver the garble is noise, so the whole block collapses
        // to one element that says what is happening and when it ends.
        .accessibilityElement(children: garbled ? .ignore : .contain)
        .accessibilityLabel(garbled
                            ? "ok. controls return in three seconds."
                            : Strings.EnjoymentPrompt.question)
    }

    private func promptButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Kroma.font(.headline, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: Kroma.Metrics.minTarget)
                .padding(.horizontal, Kroma.Space.l)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.kromaControl)
        .frame(maxWidth: 420)
    }

    private func responseMark(text: String, brokenHeart: Bool) -> some View {
        HStack(spacing: Kroma.Space.l) {
            Text(text)
                .font(Kroma.font(.largeTitle, .heavy))
                .foregroundStyle(.white)
            PerfectResponseHeart(broken: brokenHeart)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(brokenHeart ? "sorry, broken heart" : "good, heart")
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private func respond(_ response: EnjoymentResponse) {
        guard stage == .question else { return }
        responseTask?.cancel()
        switch response {
        case .yes, .no:
            engagement.recordResponse(response)
            stage = response == .yes ? .positive : .negative
            Haptics.solve()
            responseTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.25))
                guard !Task.isCancelled else { return }
                engagement.dismissPrompt()
            }
        case .stopTalking:
            // Record before the bit, not after it. The player asked to
            // never be asked again; if they background or kill the app
            // during the three seconds, that promise still has to hold.
            engagement.recordResponse(.stopTalking)
            stage = .acknowledging
            responseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                stage = .garbled
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                stage = .kidding
                try? await Task.sleep(for: .seconds(1.25))
                guard !Task.isCancelled else { return }
                engagement.dismissPrompt()
            }
        }
    }

    private func display(_ source: String, garbled: Bool) -> String {
        guard garbled else { return source }
        let glyphs = Array("▓▒░⌁⌗⋈⧖⟟⤫")
        return String(source.enumerated().map { offset, character in
            if character.isWhitespace { return character }
            if character.isPunctuation { return character }
            return glyphs[(offset * 7 + Int(character.asciiValue ?? 0)) % glyphs.count]
        })
    }
}

private struct PerfectResponseHeart: View {
    let broken: Bool

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 44))
            .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
            .overlay {
                if broken {
                    HeartCrack()
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 3,
                                                                lineCap: .round,
                                                                lineJoin: .round))
                        .frame(width: 14, height: 31)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct HeartCrack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - 3, y: rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.midX + 3, y: rect.height * 0.50))
        path.addLine(to: CGPoint(x: rect.midX - 2, y: rect.height * 0.69))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
