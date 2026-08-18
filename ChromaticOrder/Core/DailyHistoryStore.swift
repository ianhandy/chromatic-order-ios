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

enum DailyHistoryStore {
    static let key = "kromaDailyHistory_v1"

    private struct Archive: Codable {
        var firstTrackedKey: String?
        var entries: [DailyHistoryEntry]
    }

    static func entries() -> [DailyHistoryEntry] {
        load().entries.sorted { $0.dateKey > $1.dateKey }
    }

    static var firstTrackedKey: String? { load().firstTrackedKey }

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

    static func recordCompletion(
        _ dateKey: String,
        solveSeconds: Int,
        moveCount: Int,
        clean: Bool,
        usedHint: Bool
    ) {
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
        save(archive)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func load() -> Archive {
        guard let data = UserDefaults.standard.data(forKey: key),
              let archive = try? JSONDecoder().decode(Archive.self, from: data)
        else { return Archive(firstTrackedKey: nil, entries: []) }
        return archive
    }

    private static func save(_ archive: Archive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        UserDefaults.standard.set(data, forKey: key)
        CloudSync.push(key)
    }
}
