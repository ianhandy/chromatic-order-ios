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
        VStack(alignment: .leading, spacing: Kroma.Space.s) {
            Image(systemName: store.isUnlocked ? "checkmark.seal.fill" : "circle.hexagongrid.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(store.isUnlocked ? Color.green : Color.accentColor)
                .accessibilityHidden(true)

            Text(statusTitle)
                .font(Kroma.font(.title2, .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(statusDetail)
                .font(Kroma.font(.body, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusTitle: String {
        if store.isUnlocked { return "everything is unlocked" }
        if let focus, let trial = trial(for: focus), store.hasTried(trial) {
            return "thanks for trying it out!"
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
