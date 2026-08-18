import SwiftUI

struct DailyHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DailyHistoryEntry] = []
    @State private var firstTrackedKey: String?
    @State private var streak = DailyHistoryStore.streakSummary()
    @State private var reminderEnabled = StreakReminderStore.isEnabled
    @State private var sharingEnabled = StreakLeaderboardStore.isSharing
    @State private var changingReminder = false
    @State private var changingSharing = false
    @State private var settingsError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kroma.Space.xl) {
                HStack(spacing: Kroma.Space.xl) {
                    metric("current streak", streak.current, icon: "flame.fill")
                    Spacer()
                    metric("longest", streak.longest, icon: "trophy.fill")
                }

                VStack(spacing: Kroma.Space.s) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(Kroma.font(.caption, .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(calendarDates, id: \.self) { date in
                            dayCell(date)
                        }
                    }
                }

                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { reminderEnabled },
                        set: { updateReminder($0) }
                    )) {
                        settingLabel(
                            "streak reminder",
                            detail: "\(StreakReminderStore.nextReminderDescription()) · 2h before reset"
                        )
                    }
                    .disabled(changingReminder)
                    .padding(Kroma.Space.l)

                    Divider().padding(.leading, Kroma.Space.l)

                    NavigationLink {
                        StreakLeaderboardView()
                    } label: {
                        Label("longest streaks", systemImage: "list.number")
                            .font(Kroma.font(.body, .medium))
                            .frame(minHeight: Kroma.Metrics.minTarget)
                    }
                    .padding(.horizontal, Kroma.Space.l)

                    Divider().padding(.leading, Kroma.Space.l)

                    Toggle(isOn: Binding(
                        get: { sharingEnabled },
                        set: { updateSharing($0) }
                    )) {
                        settingLabel(
                            "share my best",
                            detail: "anonymous · remove anytime"
                        )
                    }
                    .disabled(changingSharing)
                    .padding(Kroma.Space.l)
                }
                .kromaSurface(
                    .control,
                    in: RoundedRectangle(cornerRadius: Kroma.Radius.card, style: .continuous)
                )

                HStack {
                    metric("completed", completedCount)
                    Spacer()
                    metric("clean", cleanCount)
                }
            }
            .padding(.horizontal, Kroma.Space.screenMargin)
            .padding(.vertical, Kroma.Space.xl)
        }
        .kromaSheet("daily history") { dismiss() }
        .onAppear {
            entries = DailyHistoryStore.entries()
            firstTrackedKey = DailyHistoryStore.firstTrackedKey
            streak = DailyHistoryStore.streakSummary()
            reminderEnabled = StreakReminderStore.isEnabled
            sharingEnabled = StreakLeaderboardStore.isSharing
        }
        .alert("setting unavailable", isPresented: Binding(
            get: { settingsError != nil },
            set: { if !$0 { settingsError = nil } }
        )) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(settingsError ?? "try again later")
        }
    }

    private func metric(_ label: String, _ value: Int, icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Kroma.Space.xs) {
            HStack(spacing: Kroma.Space.s) {
                if let icon { Image(systemName: icon) }
                Text("\(value)").monospacedDigit()
            }
            .font(Kroma.font(.title, .bold))
            Text(label)
                .font(Kroma.font(.subheadline, .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Kroma.Space.xs) {
            Text(title).font(Kroma.font(.body, .medium))
            Text(detail)
                .font(Kroma.font(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private func updateReminder(_ enabled: Bool) {
        guard !changingReminder else { return }
        changingReminder = true
        Task {
            let changed = await StreakReminderStore.setEnabled(enabled)
            await MainActor.run {
                reminderEnabled = changed ? enabled : StreakReminderStore.isEnabled
                changingReminder = false
                if !changed {
                    settingsError = "Notifications are unavailable. You can allow them in Settings."
                }
            }
        }
    }

    private func updateSharing(_ enabled: Bool) {
        guard !changingSharing else { return }
        changingSharing = true
        Task {
            let changed = await StreakLeaderboardStore.setSharing(enabled, summary: streak)
            await MainActor.run {
                sharingEnabled = changed ? enabled : StreakLeaderboardStore.isSharing
                changingSharing = false
                if !changed { settingsError = "The leaderboard could not be reached." }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let key = Daily.dateKey(now: date)
        let entry = entries.first { $0.dateKey == key }
        let today = Daily.dateKey()
        let isToday = key == today
        let tracked = firstTrackedKey.map { key >= $0 } ?? false
        let missed = tracked && key < today && entry?.completed != true

        return ZStack {
            RoundedRectangle(cornerRadius: Kroma.Radius.control, style: .continuous)
                .fill(entry?.completed == true
                      ? Color.green.opacity(0.22)
                      : Color.primary.opacity(missed ? 0.035 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: Kroma.Radius.control, style: .continuous)
                        .stroke(isToday ? Color.primary.opacity(0.85) : .clear,
                                lineWidth: isToday ? 2 : 0)
                }

            Text(dayNumber(date))
                .font(Kroma.font(.caption, .semibold))
                .foregroundStyle(missed ? .secondary : .primary)

            if entry?.completed == true {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
                    .padding(4)
            } else if missed {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topTrailing)
                    .padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullDate(date))
        .accessibilityValue(entry?.completed == true
                            ? completionValue(entry!)
                            : (isToday ? "available" : (missed ? "missed" : "not tracked")))
    }

    private var completedCount: Int { entries.filter(\.completed).count }
    private var cleanCount: Int { entries.filter { $0.completed && $0.clean == true }.count }

    private var calendarDates: [Date] {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let weekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -49, to: weekStart) ?? weekStart
        return (0..<56).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = .current
        return formatter.veryShortStandaloneWeekdaySymbols
    }

    private func dayNumber(_ date: Date) -> String {
        String(Self.calendar.component(.day, from: date))
    }

    private func fullDate(_ date: Date) -> String {
        Self.fullDateFormatter.string(from: date)
    }

    private func completionValue(_ entry: DailyHistoryEntry) -> String {
        var parts = ["completed"]
        if entry.clean == true { parts.append("clean") }
        if let seconds = entry.solveSeconds { parts.append("\(seconds) seconds") }
        if let moves = entry.moveCount { parts.append("\(moves) moves") }
        return parts.joined(separator: ", ")
    }

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1
        return calendar
    }()

    private static var fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = .current
        formatter.timeZone = Self.calendar.timeZone
        formatter.dateStyle = .long
        return formatter
    }()
}
