import SwiftUI

struct StreakLeaderboardView: View {
    @State private var entries: [StreakLeaderboardEntry] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        Group {
            if loading && entries.isEmpty {
                ProgressView()
            } else if failed && entries.isEmpty {
                ContentUnavailableView(
                    "leaderboard unavailable",
                    systemImage: "wifi.exclamationmark",
                    description: Text("pull to try again")
                )
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "no streaks yet",
                    systemImage: "flame",
                    description: Text("the first shared streak will appear here")
                )
            } else {
                List(entries) { entry in
                    HStack(spacing: Kroma.Space.m) {
                        Text("\(entry.rank)")
                            .font(Kroma.monoFont(.body, .semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                        Text(entry.handle)
                            .font(Kroma.font(.body, .medium))
                        Spacer()
                        Label("\(entry.longestStreak)", systemImage: "flame.fill")
                            .font(Kroma.monoFont(.body, .semibold))
                            .accessibilityLabel("\(entry.longestStreak) days")
                    }
                    .accessibilityElement(children: .combine)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("longest streaks")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
