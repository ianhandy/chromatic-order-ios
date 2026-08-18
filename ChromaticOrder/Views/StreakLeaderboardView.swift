import SwiftUI

struct StreakLeaderboardView: View {
    @State private var entries: [StreakLeaderboardEntry] = []
    @State private var loading = true
    @State private var failed = false
    /// Bumped on a block so the filtered list re-reads ModerationStore
    /// (UserDefaults-backed, so not observable on its own).
    @State private var moderationTick = 0
    @State private var blockNotice: String? = nil

    /// Handles are player-authored, so Guideline 1.2's blocking
    /// requirement applies here as well as in the community feed.
    private var visibleEntries: [StreakLeaderboardEntry] {
        _ = moderationTick
        return ModerationStore.filterLeaderboard(entries)
    }

    var body: some View {
        Group {
            if loading && entries.isEmpty {
                ProgressView()
            } else if failed && entries.isEmpty {
                // Was "pull to try again" — but there's no scrollable
                // container in this branch, so pull-to-refresh was
                // physically impossible and the screen was a dead end.
                ContentUnavailableView {
                    Label("leaderboard unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("check your connection")
                } actions: {
                    Button("try again") { Task { await load() } }
                }
            } else if visibleEntries.isEmpty {
                ContentUnavailableView(
                    entries.isEmpty ? "no streaks yet" : "everyone here is blocked",
                    systemImage: "flame",
                    description: Text(entries.isEmpty
                                      ? "the first shared streak will appear here"
                                      : "unblock someone to see them again")
                )
            } else {
                List(visibleEntries) { entry in
                    HStack(spacing: Kroma.Space.m) {
                        Text("\(entry.rank)")
                            .font(Kroma.monoFont(.body, .semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                        Text(entry.handle)
                            .font(Kroma.font(.body, .medium))
                        Spacer()
                        let days = entry.longestStreak
                        Label("\(days)", systemImage: "flame.fill")
                            .font(Kroma.monoFont(.body, .semibold))
                            .accessibilityLabel("\(days) day\(days == 1 ? "" : "s")")
                    }
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        Button(role: .destructive) { block(entry) } label: {
                            Label("Block \(entry.handle)", systemImage: "hand.raised")
                        }
                    }
                    .accessibilityAction(named: "Block \(entry.handle)") {
                        block(entry)
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("longest streaks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Done", isPresented: Binding(
            get: { blockNotice != nil },
            set: { if !$0 { blockNotice = nil } }
        )) {
            Button("OK", role: .cancel) { blockNotice = nil }
        } message: {
            Text(blockNotice ?? "")
        }
    }

    private func block(_ entry: StreakLeaderboardEntry) {
        ModerationStore.block(name: entry.handle)
        withAnimation { moderationTick &+= 1 }
        blockNotice = "blocked \(entry.handle)."
    }

    private func load() async {
        loading = true
        do {
            entries = try await StreakLeaderboardStore.fetch()
            failed = false
        } catch {
            failed = true
        }
        loading = false
    }
}
