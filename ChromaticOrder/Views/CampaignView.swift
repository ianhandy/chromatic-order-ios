import SwiftUI

/// A deliberately quiet campaign picker: chapter progress and local level
/// numbers are enough context before the actual board opens.
struct CampaignView: View {
    @Bindable var game: GameState
    @Binding var started: Bool
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 44, maximum: 64), spacing: 8),
        count: 5
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Kroma.Space.xxl) {
                    continueButton

                    quickAccessSection

                    ForEach(CampaignCatalog.chapters) { chapter in
                        chapterSection(chapter)
                    }
                }
                .padding(.horizontal, Kroma.Space.screenMargin)
                .padding(.vertical, Kroma.Space.xl)
            }
            .kromaSheet(Strings.Menu.campaign) { dismiss() }
        }
    }

    @ViewBuilder
    private var quickAccessSection: some View {
        let saved = CampaignStore.bookmarks
        let recent = CampaignStore.recent
        if !saved.isEmpty || !recent.isEmpty {
            VStack(alignment: .leading, spacing: Kroma.Space.l) {
                if !saved.isEmpty { quickRow("saved", levels: saved, symbol: "star.fill") }
                if !recent.isEmpty { quickRow("recent", levels: recent, symbol: "clock") }
            }
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
        Button { play(CampaignStore.nextUp) } label: {
            HStack {
                Text(CampaignStore.isComplete ? "replay" : "continue")
                    .font(Kroma.font(.title3, .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.headline)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, Kroma.Space.l)
            .padding(.vertical, Kroma.Space.m)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Kroma.Radius.card,
                                             style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.kromaControl)
        .accessibilityLabel(CampaignStore.isComplete ? "replay" : "continue")
        .accessibilityValue(continueDestination)
    }

    /// Where "continue" actually goes. Sighted players find out by
    /// tapping and seeing the board; this is the same information for
    /// anyone who wants it before committing.
    private var continueDestination: String {
        let index = CampaignStore.nextUp
        guard let chapter = CampaignCatalog.chapter(containing: index),
              let local = CampaignStore.localNumber(for: index) else { return "" }
        return "\(chapter.title.lowercased()), level \(local)"
    }

    private func chapterSection(_ chapter: CampaignChapter) -> some View {
        VStack(alignment: .leading, spacing: Kroma.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapter.title.lowercased())
                    .font(Kroma.font(.title3, .bold))
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
        let complete = CampaignStore.isCleared(level.index)
        let current = level.index == CampaignStore.nextUp
        let localNumber = CampaignStore.localNumber(for: level.index) ?? level.index

        return Button {
            guard unlocked else { return }
            play(level.index)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text("\(localNumber)")
                    .font(Kroma.font(.headline, .bold))
                    .foregroundStyle(unlocked ? .primary : .secondary)
                    .monospacedDigit()
                    .padding(.vertical, Kroma.Space.m)
                    .frame(maxWidth: .infinity, minHeight: Kroma.Metrics.minTarget)
                    .background(fill(complete: complete, unlocked: unlocked),
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
                        .font(.caption2.weight(.bold))
                        .padding(Kroma.Space.xs)
                } else if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(Kroma.Space.xs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.kromaControl)
        .disabled(!unlocked)
        // Every chapter opens at its own level 1, so the grid holds
        // several buttons labelled "1". Naming the chapter is what makes
        // them distinguishable when read out of visual context.
        .accessibilityLabel("\(chapter.title.lowercased()), level \(localNumber)")
        .accessibilityValue(complete ? "complete" : (unlocked ? "available" : "locked"))
        .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
    }

    private func fill(complete: Bool, unlocked: Bool) -> Color {
        if complete { return Color.green.opacity(0.24) }
        if unlocked { return Color.primary.opacity(0.10) }
        return Color.primary.opacity(0.04)
    }

    private func play(_ index: Int) {
        guard CampaignStore.isUnlocked(index), game.loadCampaignLevel(index) else { return }
        GlassyAudio.shared.playBloom()
        started = true
        dismiss()
    }
}
