import SwiftUI

struct DailyHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DailyHistoryEntry] = []
    @State private var firstTrackedKey: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kroma.Space.xl) {
                HStack {
                    metric("completed", completedCount)
                    Spacer()
                    metric("clean", cleanCount)
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
            }
            .padding(.horizontal, Kroma.Space.screenMargin)
            .padding(.vertical, Kroma.Space.xl)
        }
        .kromaSheet("daily history") { dismiss() }
        .onAppear {
            entries = DailyHistoryStore.entries()
            firstTrackedKey = DailyHistoryStore.firstTrackedKey
        }
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: Kroma.Space.xs) {
            Text("\(value)")
                .font(Kroma.font(.title, .bold))
                .monospacedDigit()
            Text(label)
                .font(Kroma.font(.subheadline, .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
        date.formatted(.dateTime.month(.wide).day().year())
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
}
