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
        /// Nothing on screen. The joke is the silence, not a visual
        /// effect over the top of it.
        case blank
        case kidding
    }

    var body: some View {
        ZStack {
            Kroma.Canvas.background.ignoresSafeArea()

            switch stage {
            case .positive:
                responseMark(text: Strings.EnjoymentPrompt.good, brokenHeart: false)
            case .negative:
                responseMark(text: Strings.EnjoymentPrompt.sorry, brokenHeart: true)
            case .acknowledging:
                Text(Strings.EnjoymentPrompt.okay)
                    .font(Kroma.font(.largeTitle, .heavy))
                    .foregroundStyle(Kroma.Canvas.primaryText)
                    .transition(.opacity)
            case .blank:
                // Deliberately empty: the black backdrop below is the
                // whole screen. Garbling the prompt instead read as the
                // app breaking rather than as it shutting up.
                Color.clear
                    .accessibilityElement()
                    .accessibilityLabel("ok. controls return in two seconds.")
            case .question, .kidding:
                questionContent()
                    .overlay {
                        if stage == .kidding {
                            Text(Strings.EnjoymentPrompt.justKidding)
                                .font(Kroma.font(.title2, .bold))
                                .foregroundStyle(Kroma.Canvas.primaryText)
                                .padding(.horizontal, Kroma.Space.xl)
                                .padding(.vertical, Kroma.Space.l)
                                .background(Kroma.Canvas.background, in: Capsule())
                                .overlay(Capsule().stroke(Color.primary.opacity(0.30), lineWidth: 1))
                                .shadow(color: Color.primary.opacity(0.18), radius: 18)
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

    private func questionContent() -> some View {
        VStack(spacing: Kroma.Space.xxl) {
            Spacer()

            Text(Strings.EnjoymentPrompt.question)
                .font(Kroma.font(.largeTitle, .heavy))
                .foregroundStyle(Kroma.Canvas.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Kroma.Space.m) {
                promptButton(Strings.EnjoymentPrompt.yes) {
                    respond(.yes)
                }
                promptButton(Strings.EnjoymentPrompt.no) {
                    respond(.no)
                }
                promptButton(Strings.EnjoymentPrompt.stopTalking) {
                    respond(.stopTalking)
                }
            }
            .disabled(stage != .question)

            Spacer()
        }
        .padding(.horizontal, Kroma.Space.xxl)
        .padding(.vertical, Kroma.Space.xxl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.EnjoymentPrompt.question)
    }

    private func promptButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Kroma.font(.headline, .bold))
                .foregroundStyle(Kroma.Canvas.primaryText)
                .frame(maxWidth: .infinity, minHeight: Kroma.Metrics.minTarget)
                .padding(.horizontal, Kroma.Space.l)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.24), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.kromaControl)
        .frame(maxWidth: 420)
    }

    private func responseMark(text: String, brokenHeart: Bool) -> some View {
        HStack(spacing: Kroma.Space.l) {
            Text(text)
                .font(Kroma.font(.largeTitle, .heavy))
                .foregroundStyle(Kroma.Canvas.primaryText)
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
                stage = .blank
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                stage = .kidding
                try? await Task.sleep(for: .seconds(1.25))
                guard !Task.isCancelled else { return }
                engagement.dismissPrompt()
            }
        }
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
