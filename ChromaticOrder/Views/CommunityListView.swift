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
        // Prefer the doc's `name` (creator-typed title) over the legacy
        // `submitterName` field — both carry the same value on new
        // submissions but the doc field is the canonical source.
        let title = entry.doc.name ?? entry.submitterName
        game.loadCustomPuzzle(puzzle, title: title)
        dismiss()
    }
}

/// One row in the community list. Two states:
///
///   • Compact: thumbnail + title/subtitle + vote count summary.
///     Tap anywhere to expand.
///   • Expanded: full-width detail panel grows downward in place,
///     swapping the "Lv N" chip for a back arrow that collapses
///     the row. Difficulty surfaces here, the like / dislike
///     arrows are full-size (matching LikeFeedbackWidget's
///     arrowtriangle pair), and a Play button is the only path
///     into the actual puzzle. A bare row tap no longer plays —
///     the user has to expand first, look the puzzle over, then
///     hit Play. Voting works in either state via the same
///     optimistic-flip mechanism.
private struct CommunityRow: View {
    @Binding var entry: CommunityPuzzleEntry
    let onPlay: () -> Void
    @State private var voting: Bool = false
    @State private var expanded: Bool = false

    private let likeGreen  = Color(red: 0.36, green: 0.78, blue: 0.45)
    private let dislikeRed = Color(red: 0.92, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            if expanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                expanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var compactHeader: some View {
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
            Spacer()
            // Compact vote summary — no buttons here, the player
            // votes from the expanded panel where the arrows are
            // full-size.
            HStack(spacing: 8) {
                Label("\(entry.upCount)", systemImage: "arrowtriangle.up.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(entry.myVote == 1
                                      ? likeGreen : Color.secondary)
                Label("\(entry.downCount)", systemImage: "arrowtriangle.down.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(entry.myVote == -1
                                      ? dislikeRed : Color.secondary)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: back-arrow takes the spot the lv chip used
            // to occupy, and on the right the play button mounts the
            // puzzle in the game (the only way to actually play now —
            // a bare tap on the row toggles expansion, not load).
            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        expanded = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.primary)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold,
                                       design: .rounded))
                        .lineLimit(1)
                    Text(difficultyLabel)
                        .font(.system(size: 13, weight: .bold,
                                       design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onPlay()
                } label: {
                    Text("Play")
                        .font(.system(size: 14, weight: .heavy,
                                       design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            // Full-size arrow vote controls — matches the
            // LikeFeedbackWidget styling so the feedback arrows feel
            // consistent across the app.
            HStack(spacing: 18) {
                voteArrow(direction: +1, color: likeGreen,
                          system: "arrowtriangle.up.fill",
                          count: entry.upCount)
                voteArrow(direction: -1, color: dislikeRed,
                          system: "arrowtriangle.down.fill",
                          count: entry.downCount)
                Spacer()
            }
            .padding(.leading, 4)
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
        // Stop the outer tap-to-expand from firing on inner buttons.
        .contentShape(Rectangle())
        .onTapGesture { /* swallow */ }
    }

    @ViewBuilder
    private func voteArrow(direction: Int, color: Color,
                            system: String, count: Int) -> some View {
        let active = entry.myVote == direction
        Button {
            cast(direction)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(active ? color : Color.secondary)
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold,
                                   design: .rounded))
                    .foregroundStyle(active ? color : Color.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(active
                                ? color.opacity(0.14)
                                : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(voting)
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
    private var name: String {
        if let n = entry.submitterName, !n.isEmpty { return n }
        return "Untitled"
    }
    private var difficultyLabel: String {
        "difficulty \(entry.doc.difficulty ?? 0)/10"
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
