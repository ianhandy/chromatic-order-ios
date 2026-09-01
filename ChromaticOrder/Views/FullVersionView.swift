import SwiftUI

enum FullVersionFeature {
    case campaign
    case zen
    case challenge
    case creator

    var title: String {
        switch self {
        case .campaign:  return "the full campaign"
        case .zen:       return "infinite zen"
        case .challenge: return "challenge runs"
        case .creator:   return "puzzle creator"
        }
    }

    var detail: String {
        switch self {
        case .campaign:
            return "continue through all 200 handcrafted campaign puzzles."
        case .zen:
            return "truly infinite, procedurally generated puzzles at a difficulty you choose."
        case .challenge:
            return "start with three hearts and climb through harder puzzles."
        case .creator:
            return "build and share your own custom color puzzles."
        }
    }

    var symbol: String {
        switch self {
        case .campaign:  return "square.grid.3x3.fill"
        case .zen:       return "infinity"
        case .challenge: return "heart.fill"
        case .creator:   return "paintpalette.fill"
        }
    }
}

struct FullVersionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FullVersionStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let focus: FullVersionFeature?

    init(focus: FullVersionFeature? = nil) {
        self.focus = focus
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Kroma.Space.xxl) {
                    statusMark

                    VStack(alignment: .leading, spacing: Kroma.Space.l) {
                        feature(.campaign)
                        feature(.zen)
                        feature(.challenge)
                        feature(.creator)
                    }
                    .accessibilityElement(children: .contain)

                    if !store.isUnlocked {
                        trialAvailability
                    }

                    purchaseControls
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, Kroma.Space.screenMargin)
                .padding(.vertical, Kroma.Space.xxl)
            }
            .kromaSheet("full version") { dismiss() }
        }
    }

    private var statusMark: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: Kroma.Space.s) {
                Image(systemName: store.isUnlocked ? "checkmark.seal.fill" : "circle.hexagongrid.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(store.isUnlocked ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)

                Text(statusTitle(at: context.date))
                    .font(Kroma.font(.title2, .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(statusDetail)
                    .font(Kroma.font(.body, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusTitle(at now: Date) -> String {
        if store.isUnlocked { return "everything is unlocked" }
        if let focus,
           let trial = trial(for: focus),
           !store.canTry(trial, now: now),
           let availableAt = store.nextTrialAvailability(trial),
           availableAt > now {
            let remaining = Self.countdown(from: now, until: availableAt)
            return Self.cooldownPurchaseTitle(remaining: remaining)
        }
        return focus?.title ?? "one purchase. the whole game."
    }

    private func trial(for feature: FullVersionFeature) -> FullVersionTrial? {
        switch feature {
        case .zen: return .zen
        case .challenge: return .challenge
        case .creator: return .creator
        case .campaign: return nil
        }
    }

    private var statusDetail: String {
        if store.isUnlocked { return "the full game is available on this Apple Account." }
        return focus?.detail
            ?? "Today’s Puzzle, the Gallery, and the first four campaign chapters stay free."
    }

    private func feature(_ feature: FullVersionFeature) -> some View {
        HStack(alignment: .top, spacing: Kroma.Space.m) {
            Image(systemName: feature.symbol)
                .font(Kroma.font(.headline, .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28, alignment: .top)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Kroma.Space.xs) {
                Text(feature.title)
                    .font(Kroma.font(.headline, .semibold))
                Text(feature.detail)
                    .font(Kroma.font(.subheadline, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var trialAvailability: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let zenAvailableAt = coolingAvailability(.zen, at: context.date)
            let challengeAvailableAt = coolingAvailability(.challenge, at: context.date)

            if zenAvailableAt != nil || challengeAvailableAt != nil {
                VStack(alignment: .leading, spacing: Kroma.Space.m) {
                    VStack(alignment: .leading, spacing: Kroma.Space.xs) {
                        Text(Strings.FullVersion.waitTitle)
                            .font(Kroma.font(.headline, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Strings.FullVersion.waitBody)
                            .font(Kroma.font(.subheadline, .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: Kroma.Space.s) {
                        if let zenAvailableAt {
                            trialAvailabilityRow(
                                .zen,
                                at: context.date,
                                availableAt: zenAvailableAt
                            )
                        }
                        if let challengeAvailableAt {
                            trialAvailabilityRow(
                                .challenge,
                                at: context.date,
                                availableAt: challengeAvailableAt
                            )
                        }
                    }
                }
                .padding(Kroma.Space.l)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
        }
    }

    private func coolingAvailability(
        _ trial: FullVersionTrial,
        at now: Date
    ) -> Date? {
        guard !store.canTry(trial, now: now),
              let availableAt = store.nextTrialAvailability(trial),
              availableAt > now else { return nil }
        return availableAt
    }

    private func trialAvailabilityRow(
        _ trial: FullVersionTrial,
        at now: Date,
        availableAt: Date
    ) -> some View {
        let name = trial == .zen ? Strings.Menu.zen : Strings.Menu.challenge
        let status = "in \(Self.countdown(from: now, until: availableAt))"

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Kroma.Space.xs) {
                    trialName(name)
                    trialStatus(status)
                        .padding(.leading, 22 + Kroma.Space.m)
                }
            } else {
                HStack(alignment: .center, spacing: Kroma.Space.m) {
                    trialName(name)
                    Spacer(minLength: Kroma.Space.m)
                    trialStatus(status)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(minHeight: Kroma.Metrics.minTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("available \(status)")
    }

    private func trialName(_ name: String) -> some View {
        HStack(alignment: .center, spacing: Kroma.Space.m) {
            Image(systemName: "timer")
                .font(Kroma.font(.subheadline, .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(name)
                .font(Kroma.font(.body, .semibold))
        }
    }

    private func trialStatus(_ status: String) -> some View {
        Text(status)
            .font(Kroma.font(.subheadline, .semibold))
            .foregroundStyle(Color.secondary)
    }

    static func countdown(from now: Date, until date: Date) -> String {
        let seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(remainingSeconds)s" }
        return "\(remainingSeconds)s"
    }

    static func cooldownPurchaseTitle(remaining: String) -> String {
        "wait \(remaining) or purchase the full version"
    }

    @ViewBuilder
    private var purchaseControls: some View {
        VStack(spacing: Kroma.Space.m) {
            if store.isUnlocked {
                Button("done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            } else if let product = store.product {
                Button {
                    Task { await store.purchase() }
                } label: {
                    HStack(spacing: Kroma.Space.s) {
                        if store.isPurchasing { ProgressView() }
                        Text("unlock · \(product.displayPrice)")
                    }
                    .font(Kroma.font(.headline, .bold))
                    .frame(maxWidth: .infinity, minHeight: Kroma.Metrics.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isPurchasing)
                .accessibilityHint("one-time purchase")
            } else {
                Button {
                    Task { await store.reloadProduct() }
                } label: {
                    HStack(spacing: Kroma.Space.s) {
                        if store.isLoading { ProgressView() }
                        Text(store.isLoading ? "loading" : "try again")
                    }
                    .font(Kroma.font(.headline, .bold))
                    .frame(maxWidth: .infinity, minHeight: Kroma.Metrics.minTarget)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isLoading)
            }

            if let notice = store.notice {
                Text(notice)
                    .font(Kroma.font(.subheadline, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if !store.isUnlocked {
                Button("restore purchase") {
                    Task { await store.restore() }
                }
                .font(Kroma.font(.subheadline, .semibold))
                .frame(minHeight: Kroma.Metrics.minTarget)
                .disabled(store.isPurchasing)
            }

            Text("one-time purchase · no subscription")
                .font(Kroma.font(.caption, .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }
}
