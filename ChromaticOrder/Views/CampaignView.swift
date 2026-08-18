import SwiftUI

/// A deliberately quiet campaign picker: chapter progress and local level
/// numbers are enough context before the actual board opens.
struct CampaignView: View {
    @Bindable var game: GameState
    @Binding var started: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(FullVersionStore.self) private var fullVersion
    @State private var positionedAtProgress = false
    @State private var fullVersionOpen = false

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 44, maximum: 64), spacing: 8),
        count: 5
    )

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Kroma.Space.xxl) {
                        quickAccessSection

                        ForEach(CampaignCatalog.chapters) { chapter in
                            chapterSection(chapter)
                                .id(chapter.id)
                        }
                    }
                    .padding(.horizontal, Kroma.Space.screenMargin)
                    .padding(.vertical, Kroma.Space.xl)
                }
                .task {
                    guard !positionedAtProgress,
                          let chapter = CampaignStore.resumeChapter else { return }
                    positionedAtProgress = true
                    // Let the lazy stack establish its content before placing
                    // the relevant chapter at the top. This is initial state,
                    // not a navigation event, so it intentionally doesn't fly
                    // past chapters the player has already completed.
                    await Task.yield()
                    proxy.scrollTo(chapter.id, anchor: .top)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                continueButton
                    .padding(.horizontal, Kroma.Space.screenMargin)
                    .padding(.vertical, Kroma.Space.m)
                    .background(.regularMaterial)
            }
            .kromaSheet(Strings.Menu.campaign) { dismiss() }
        }
        .sheet(isPresented: $fullVersionOpen) {
            FullVersionView(focus: .campaign)
        }
    }

    @ViewBuilder
    private var quickAccessSection: some View {
        let saved = CampaignStore.bookmarks
        if !saved.isEmpty {
            quickRow("saved", levels: saved, symbol: "star.fill")
        }
    }

    private func quickRow(_ title: String, levels: [Int], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Kroma.Space.s) {
            Label(title, systemImage: symbol)
                .font(Kroma.font(.subheadline, .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Kroma.Space.s) {
                    ForEach(levels, id: \.self) { index in
                        Button { play(index) } label: {
                            Text(shortLevelName(index))
                                .font(Kroma.font(.subheadline, .bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, Kroma.Space.m)
                                .frame(minHeight: Kroma.Metrics.minTarget)
                                .background(Color.primary.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.kromaControl)
                        .accessibilityLabel(accessibleLevelName(index))
                    }
                }
            }
        }
    }

    private func shortLevelName(_ index: Int) -> String {
        guard let chapter = CampaignCatalog.chapter(containing: index),
              let local = CampaignStore.localNumber(for: index) else { return "\(index)" }
        return "\(chapter.title.lowercased()) \(local)"
    }

    private func accessibleLevelName(_ index: Int) -> String {
        guard let chapter = CampaignCatalog.chapter(containing: index),
              let local = CampaignStore.localNumber(for: index) else { return "level \(index)" }
        return "\(chapter.title.lowercased()), level \(local)"
    }

    private var continueButton: some View {
        let purchaseLocked = FullVersionAccess.campaignLevelRequiresPurchase(CampaignStore.nextUp)
            && !fullVersion.isUnlocked

        return Button { play(CampaignStore.nextUp) } label: {
            HStack(spacing: Kroma.Space.m) {
                Image(systemName: purchaseLocked
                      ? "lock.open.fill"
                      : (CampaignStore.isComplete ? "arrow.counterclockwise" : "play.fill"))
                    .font(Kroma.font(.headline, .bold))

                VStack(alignment: .leading, spacing: Kroma.Space.hairline) {
                    Text(purchaseLocked
                         ? "unlock full campaign"
                         : (CampaignStore.isComplete ? "replay campaign" : "continue"))
                        .font(Kroma.font(.headline, .bold))
                    Text(continueDestination)
                        .font(Kroma.font(.caption, .semibold))
                        .opacity(0.78)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(Kroma.font(.subheadline, .bold))
            }
            .foregroundStyle(continueForeground)
            .padding(.horizontal, Kroma.Space.l)
            .padding(.vertical, Kroma.Space.m)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.accentColor,
                        in: RoundedRectangle(cornerRadius: Kroma.Radius.card,
                                             style: .continuous))
            .shadow(color: Color.accentColor.opacity(0.24), radius: 10, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.kromaControl)
        .accessibilityLabel(purchaseLocked
                            ? "unlock full campaign"
                            : (CampaignStore.isComplete ? "replay campaign" : "continue campaign"))
        .accessibilityValue(continueDestination)
    }

    /// AccentColor is a deeper cyan in normal Light Mode and a bright cyan
    /// in Dark Mode. Its high-contrast Light variant crosses the point where
    /// white becomes the stronger pairing, so the label follows that asset.
    private var continueForeground: Color {
        colorScheme == .light && colorSchemeContrast == .increased
            ? .white
            : .black
    }

    /// Where the persistent primary action goes, visible and announced.
    private var continueDestination: String {
        let index = CampaignStore.nextUp
        guard let chapter = CampaignCatalog.chapter(containing: index),
              let local = CampaignStore.localNumber(for: index) else { return "" }
        return "\(chapter.title.lowercased()), level \(local)"
    }

    private func chapterSection(_ chapter: CampaignChapter) -> some View {
        let purchaseLocked = FullVersionAccess.campaignLevelRequiresPurchase(chapter.first)
            && !fullVersion.isUnlocked

        return VStack(alignment: .leading, spacing: Kroma.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapter.title.lowercased())
                    .font(Kroma.font(.title3, .bold))
                if purchaseLocked {
                    Image(systemName: "lock.fill")
                        .font(Kroma.font(.caption, .bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Text("\(CampaignStore.chapterCompletion(chapter))/\(chapter.count)")
                    .font(Kroma.font(.subheadline, .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // One element, one announcement: without this VoiceOver
            // reads the chapter name and its fraction as two unrelated
            // strings before it reaches the levels.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: Kroma.Space.s) {
                ForEach(CampaignCatalog.levels(in: chapter)) { level in
                    levelButton(level, chapter: chapter)
                }
            }
        }
    }

    private func levelButton(_ level: CampaignLevel,
                             chapter: CampaignChapter) -> some View {
        let unlocked = CampaignStore.isUnlocked(level.index)
        let purchaseLocked = FullVersionAccess.campaignLevelRequiresPurchase(level.index)
            && !fullVersion.isUnlocked
        let complete = CampaignStore.isCleared(level.index)
        let current = level.index == CampaignStore.nextUp
        let localNumber = CampaignStore.localNumber(for: level.index) ?? level.index

        return Button {
            if purchaseLocked {
                fullVersionOpen = true
                return
            }
            guard unlocked else { return }
            play(level.index)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text("\(localNumber)")
                    .font(Kroma.font(.headline, .bold))
                    .foregroundStyle(unlocked && !purchaseLocked ? .primary : .secondary)
                    .monospacedDigit()
                    .padding(.vertical, Kroma.Space.m)
                    .frame(maxWidth: .infinity, minHeight: Kroma.Metrics.minTarget)
                    .background(fill(complete: complete,
                                     unlocked: unlocked,
                                     purchaseLocked: purchaseLocked),
                                in: RoundedRectangle(cornerRadius: Kroma.Radius.control,
                                                     style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Kroma.Radius.control,
                                         style: .continuous)
                            .stroke(current ? Color.primary.opacity(0.65) : .clear,
                                    lineWidth: current ? 2 : 0)
                    }

                // Cleared is a green fill *and* a checkmark; locked is a
                // dim fill *and* a padlock. Neither state is carried by
                // colour on its own.
                if complete {
                    Image(systemName: "checkmark")
                        .font(Kroma.font(.caption2, .bold))
                        .padding(Kroma.Space.xs)
                } else if !unlocked || purchaseLocked {
                    Image(systemName: "lock.fill")
                        .font(Kroma.font(.caption2, .bold))
                        .foregroundStyle(.secondary)
                        .padding(Kroma.Space.xs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.kromaControl)
        .disabled(!unlocked && !purchaseLocked)
        // Every chapter opens at its own level 1, so the grid holds
        // several buttons labelled "1". Naming the chapter is what makes
        // them distinguishable when read out of visual context.
        .accessibilityLabel("\(chapter.title.lowercased()), level \(localNumber)")
        .accessibilityValue(complete
                            ? "complete"
                            : (purchaseLocked
                               ? "requires full version"
                               : (unlocked ? "available" : "locked")))
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    private func fill(complete: Bool, unlocked: Bool, purchaseLocked: Bool) -> Color {
        if complete { return Color.green.opacity(0.24) }
        if unlocked && !purchaseLocked { return Color.primary.opacity(0.10) }
        return Color.primary.opacity(0.04)
    }

    private func play(_ index: Int) {
        if FullVersionAccess.campaignLevelRequiresPurchase(index),
           !fullVersion.isUnlocked {
            fullVersionOpen = true
            return
        }
        guard CampaignStore.isUnlocked(index), game.loadCampaignLevel(index) else { return }
        started = true
        dismiss()
    }
}
