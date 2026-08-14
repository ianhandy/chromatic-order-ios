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
                LazyVStack(alignment: .leading, spacing: 32) {
                    continueButton

                    ForEach(CampaignCatalog.chapters) { chapter in
                        chapterSection(chapter)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
        }
    }

    private var continueButton: some View {
        Button { play(CampaignStore.nextUp) } label: {
            HStack {
                Text(CampaignStore.isComplete ? "replay" : "continue")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16,
                                                                            style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CampaignStore.isComplete ? "replay" : "continue")
    }

    private func chapterSection(_ chapter: CampaignChapter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapter.title.lowercased())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                Text("\(CampaignStore.chapterCompletion(chapter))/\(chapter.count)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CampaignCatalog.levels(in: chapter)) { level in
                    levelButton(level)
                }
            }
        }
    }

    private func levelButton(_ level: CampaignLevel) -> some View {
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
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(unlocked ? .primary : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(fill(complete: complete, unlocked: unlocked),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(current ? Color.primary.opacity(0.65) : .clear,
                                    lineWidth: current ? 2 : 0)
                    }

                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(6)
                } else if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("level \(localNumber)")
        .accessibilityValue(complete ? "complete" : (unlocked ? "available" : "locked"))
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
