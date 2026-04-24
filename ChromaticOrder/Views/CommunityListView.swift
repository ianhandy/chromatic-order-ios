//  Community-submitted puzzles browser. Lists server-approved
//  puzzles, lets the player up/down-vote each, and drops them into
//  the game via `GameState.loadCustomPuzzle(_:)` on tap.
//
//  Voting is backed by a Keychain-stored voterId (CommunityStore)
//  so UserDefaults resets don't let a single device cycle identities.
//  The admin moderation queue on the server is the actual content
//  gate; voting only drives sort order of already-approved puzzles.

import SwiftUI

struct CommunityListView: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [CommunityPuzzleEntry] = []
    @State private var sort: CommunitySort = .top
    @State private var loading: Bool = false
    @State private var loadError: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if loading && entries.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading community puzzles…")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach($entries) { $entry in
                            CommunityRow(entry: $entry,
                                         onPlay: { play(entry) })
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Sort", selection: $sort) {
                        Text("Top").tag(CommunitySort.top)
                        Text("New").tag(CommunitySort.new)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                }
            }
            .task { await refresh() }
            .onChange(of: sort) { _, _ in
                Task { await refresh() }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(loadError != nil
                 ? "Couldn't load the community feed."
                 : "No community puzzles yet.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            if let err = loadError {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Try again") { Task { await refresh() } }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() async {
        await MainActor.run { loading = true; loadError = nil }
        let (fetched, ok) = await CommunityStore.fetchFeed(sort: sort, limit: 50)
        await MainActor.run {
            loading = false
            if ok {
                entries = fetched
            } else if entries.isEmpty {
                loadError = "network unavailable"
            }
        }
    }

    private func play(_ entry: CommunityPuzzleEntry) {
        guard let puzzle = CreatorCodec.rebuild(entry.doc, level: entry.level) else { return }
        game.loadCustomPuzzle(puzzle)
        dismiss()
    }
}

/// One row in the community list. Renders a compact thumbnail
/// (reusing the in-house PuzzlePreviewRenderer), title, submitter,
/// score, and thumbs-up / thumbs-down buttons that optimistically
/// flip local state while the vote POST is in flight.
private struct CommunityRow: View {
    @Binding var entry: CommunityPuzzleEntry
    let onPlay: () -> Void
    @State private var voting: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onPlay()
            } label: {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            voteControls
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let puzzle = CreatorCodec.rebuild(entry.doc, level: entry.level),
           let img = PuzzlePreviewRenderer.render(puzzle) {
            img
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 52, height: 52)
        }
    }

    private var title: String {
        if let name = entry.submitterName, !name.isEmpty { return name }
        return "Lv \(entry.level) · diff \(entry.doc.difficulty ?? 0)/10"
    }
    private var subtitle: String {
        "lv \(entry.level) · \(entry.doc.gridW)×\(entry.doc.gridH)"
    }

    @ViewBuilder
    private var voteControls: some View {
        HStack(spacing: 10) {
            Button { cast(+1) } label: {
                HStack(spacing: 3) {
                    Image(systemName: entry.myVote == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    Text("\(entry.upCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(entry.myVote == 1 ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            Button { cast(-1) } label: {
                HStack(spacing: 3) {
                    Image(systemName: entry.myVote == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    Text("\(entry.downCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(entry.myVote == -1 ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
        }
        .disabled(voting)
    }

    /// Cast or retract a vote. If the player taps the same direction
    /// they already picked, the vote is retracted (sent as 0).
    private func cast(_ direction: Int) {
        let next = entry.myVote == direction ? 0 : direction
        voting = true
        // Optimistic flip — the server's recounted numbers overwrite
        // these on response. Rolls back on failure.
        let prior = entry
        applyOptimistic(next)
        Task {
            let result = await CommunityStore.vote(
                puzzleId: entry.id, vote: next
            )
            await MainActor.run {
                voting = false
                switch result {
                case .success(let resp):
                    if let up = resp.upCount { entry.upCount = up }
                    if let down = resp.downCount { entry.downCount = down }
                    if let score = resp.score { entry.score = score }
                    entry.myVote = resp.myVote ?? next
                case .failure:
                    entry = prior
                }
            }
        }
    }

    private func applyOptimistic(_ next: Int) {
        let prev = entry.myVote
        if prev == next { return }
        if prev == 1 { entry.upCount = max(0, entry.upCount - 1) }
        if prev == -1 { entry.downCount = max(0, entry.downCount - 1) }
        if next == 1 { entry.upCount += 1 }
        if next == -1 { entry.downCount += 1 }
        entry.myVote = next
        entry.score = entry.upCount - entry.downCount
    }
}
