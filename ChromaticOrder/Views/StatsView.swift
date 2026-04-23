//  Player statistics sheet. Loads StatsStore on appear — static view
//  of whatever the game has recorded so far. Lives behind the main
//  menu's "stats" button.

import SwiftUI

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stats: Stats = StatsStore.load()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Total solves", "\(stats.totalSolves)")
                    row("Zen", "\(stats.zenSolves)")
                    row("Challenge", "\(stats.challengeSolves)")
                    row("Daily", "\(stats.dailySolves)")
                } header: {
                    Text("Solves")
                }

                Section {
                    row("Longest clean streak", "\(stats.longestCleanStreak)")
                    row("Current streak", "\(stats.currentCleanStreak)")
                } header: {
                    Text("Streaks")
                } footer: {
                    Text("A clean solve is zero mistakes and no \"show incorrect\" peek.")
                }

                Section {
                    row("Total time solving", formatDuration(stats.totalSolveSeconds))
                    row("Avg per solve", averageSolveTime)
                } header: {
                    Text("Time")
                }

                if !stats.cbModesSeen.isEmpty {
                    Section {
                        ForEach(stats.cbModesSeen, id: \.self) { m in
                            Text(m.capitalized)
                        }
                    } header: {
                        Text("Color vision modes tried")
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { stats = StatsStore.load() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var averageSolveTime: String {
        guard stats.totalSolves > 0 else { return "—" }
        return formatDuration(stats.totalSolveSeconds / stats.totalSolves)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
