import Foundation

struct DailyHistoryEntry: Codable, Hashable, Identifiable {
    let dateKey: String
    var completed: Bool
    var solveSeconds: Int?
    var moveCount: Int?
    var clean: Bool?
    var usedHint: Bool?

    var id: String { dateKey }
}

struct DailyStreakSummary: Equatable {
    let current: Int
    let longest: Int
    let completedThrough: String?
}

enum DailyHistoryStore {
    static let key = "kromaDailyHistory_v1"

    private struct Archive: Codable {
        var firstTrackedKey: String?
        var entries: [DailyHistoryEntry]
        var longestStreak: Int?
    }

    static func entries() -> [DailyHistoryEntry] {
        load().entries.sorted { $0.dateKey > $1.dateKey }
    }

    static var firstTrackedKey: String? { load().firstTrackedKey }

    static func streakSummary(now: Date = Date()) -> DailyStreakSummary {
        summary(for: load(), now: now)
    }

    static func recordAttempt(_ dateKey: String) {
        var archive = load()
        if archive.firstTrackedKey == nil || dateKey < archive.firstTrackedKey! {
            archive.firstTrackedKey = dateKey
        }
        if !archive.entries.contains(where: { $0.dateKey == dateKey }) {
            archive.entries.append(DailyHistoryEntry(
                dateKey: dateKey, completed: false,
                solveSeconds: nil, moveCount: nil, clean: nil, usedHint: nil
            ))
        }
        save(archive)
    }

    @discardableResult
    static func recordCompletion(
        _ dateKey: String,
        solveSeconds: Int,
        moveCount: Int,
        clean: Bool,
        usedHint: Bool
    ) -> DailyStreakSummary {
        var archive = load()
        if archive.firstTrackedKey == nil || dateKey < archive.firstTrackedKey! {
            archive.firstTrackedKey = dateKey
        }
        let entry = DailyHistoryEntry(
            dateKey: dateKey,
            completed: true,
            solveSeconds: solveSeconds,
            moveCount: moveCount,
            clean: clean,
            usedHint: usedHint
        )
        if let index = archive.entries.firstIndex(where: { $0.dateKey == dateKey }) {
            archive.entries[index] = entry
        } else {
            archive.entries.append(entry)
        }
        // Enough for a full year view while keeping the defaults payload tiny.
        archive.entries = Array(archive.entries.sorted { $0.dateKey > $1.dateKey }.prefix(370))
        let computed = summary(for: archive, now: Date())
        archive.longestStreak = max(archive.longestStreak ?? 0, computed.longest)
        save(archive)
        return summary(for: archive, now: Date())
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func load() -> Archive {
        guard let data = UserDefaults.standard.data(forKey: key),
              let archive = try? JSONDecoder().decode(Archive.self, from: data)
        else { return Archive(firstTrackedKey: nil, entries: [], longestStreak: nil) }
        return archive
    }

    private static func summary(for archive: Archive, now: Date) -> DailyStreakSummary {
        let completed = Set(archive.entries.filter(\.completed).map(\.dateKey))
        let today = Daily.dateKey(now: now)
        let yesterday = shifted(today, by: -1)
        let anchor = completed.contains(today) ? today
            : (yesterday.map(completed.contains) == true ? yesterday : nil)

        var current = 0
        var cursor = anchor
        while let key = cursor, completed.contains(key) {
            current += 1
            cursor = shifted(key, by: -1)
        }

        var run = 0
        var calculatedLongest = 0
        var previous: String?
        for key in completed.sorted() {
            if let previous, shifted(previous, by: 1) == key {
                run += 1
            } else {
                run = 1
            }
            calculatedLongest = max(calculatedLongest, run)
            previous = key
        }

        return DailyStreakSummary(
            current: current,
            longest: max(calculatedLongest, archive.longestStreak ?? 0),
            completedThrough: completed.max()
        )
    }

    private static func shifted(_ key: String, by days: Int) -> String? {
        guard let date = utcFormatter.date(from: key),
              let shifted = utcCalendar.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return utcFormatter.string(from: shifted)
    }

    private static var utcCalendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    private static var utcFormatter: DateFormatter = {
        let value = DateFormatter()
        value.calendar = utcCalendar
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = TimeZone(secondsFromGMT: 0)
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static func save(_ archive: Archive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        UserDefaults.standard.set(data, forKey: key)
        CloudSync.push(key)
    }
}
