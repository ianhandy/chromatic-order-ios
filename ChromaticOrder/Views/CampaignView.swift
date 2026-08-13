//  Campaign level picker. Seven chapters, 100 authored levels, unlocked one
//  at a time. Each row shows the shape's name and a swatch strip pulled
//  from the level's own palette, so the list reads as a colour journal of
//  everything the player has solved.

import SwiftUI

struct CampaignView: View {
    @Bindable var game: GameState
    @Binding var started: Bool
    @Environment(\.dismiss) private var dismiss

    /// Re-read on every appear: clearing a level while this sheet is closed
    /// has to show up when it re-opens.
    @State private var cleared: Set<Int> = CampaignStore.cleared()

    private var nextUp: Int { CampaignStore.nextUp }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                ForEach(CampaignCatalog.chapters) { chapter in
                    Section {
                        ForEach(CampaignCatalog.levels(in: chapter)) { level in
                            row(for: level)
                        }
                    } header: {
                        chapterHeader(chapter)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close") { dismiss() }
                }
            }
        }
        .onAppear { cleared = CampaignStore.cleared() }
    }

    // ─── Sections ──────────────────────────────────────────────────

    private var headerSection: some View {
        Section {
            Button {
                play(nextUp)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CampaignStore.isComplete ? "replay the last shape" : "continue")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        if let level = CampaignCatalog.level(nextUp) {
                            Text("\(nextUp). \(level.name) · \(level.chapter)")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(cleared.count)/\(CampaignCatalog.count)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("100 shapes, in order. Each one adds a little to what the "
                 + "last one taught you.")
        }
    }

    private func chapterHeader(_ chapter: CampaignChapter) -> some View {
        let done = chapter.levelRange.filter { cleared.contains($0) }.count
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(chapter.title.lowercased())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(done)/\(chapter.count)")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(chapter.blurb)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .padding(.vertical, 2)
    }

    private func row(for level: CampaignLevel) -> some View {
        let unlocked = level.index <= 1 || cleared.contains(level.index)
            || cleared.contains(level.index - 1)
        let isDone = cleared.contains(level.index)
        return Button {
            guard unlocked else { return }
            play(level.index)
        } label: {
            HStack(spacing: 12) {
                Text("\(level.index)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(level.name)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(unlocked ? .primary : .secondary)
                    Text("\(level.gradientCount) gradient\(level.gradientCount == 1 ? "" : "s")"
                         + " · \(level.bankCount) to place")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if unlocked {
                    paletteStrip(level)
                }
                Image(systemName: isDone ? "checkmark.circle.fill"
                      : (unlocked ? "chevron.right" : "lock.fill"))
                    .font(.system(size: isDone ? 15 : 12, weight: .semibold))
                    .foregroundStyle(isDone ? Color.green.opacity(0.8) : .secondary)
            }
        }
        .disabled(!unlocked)
    }

    /// Five colours sampled across the level's own gradients — a thumbnail
    /// of the palette without rendering the whole board.
    private func paletteStrip(_ level: CampaignLevel) -> some View {
        let colors: [OKLCh] = level.doc.gradients.prefix(5).compactMap { grad in
            guard let cell = grad.cells.first else { return nil }
            return OKLCh(L: cell.L, c: cell.C, h: cell.h)
        }
        return HStack(spacing: 2) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2)
                    .fill(OK.toColor(color))
                    .frame(width: 8, height: 14)
            }
        }
    }

    // ─── Actions ───────────────────────────────────────────────────

    private func play(_ index: Int) {
        guard game.loadCampaignLevel(index) else { return }
        GlassyAudio.shared.playBloom()
        // Same order the gallery uses: flip `started` first so the game view
        // is already mounted behind the sheet as it slides away.
        started = true
        dismiss()
    }
}
