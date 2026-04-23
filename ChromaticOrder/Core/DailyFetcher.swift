//  Async fetch of the shared daily puzzle from the kroma web API.
//  Cached in UserDefaults by UTC date so repeated launches in the
//  same day don't re-roundtrip, and the player can play offline
//  after a single successful fetch. Returns nil on any network or
//  decode failure — callers should fall back to their local seeded
//  generation path, accepting that offline play will diverge from
//  other clients' puzzles for that day.
//
//  Server: `GET https://kroma.ianhandy.com/api/daily?date=YYYY-MM-DD`
//  Response: `{ date, level, difficulty?, doc: CreatorPuzzleDoc, ... }`

import Foundation

enum DailyFetcher {
    private static let cacheKeyPrefix = "kroma.daily.cache."

    /// Response envelope from `/api/daily`. `doc` is the embedded
    /// CreatorPuzzleDoc that the client rebuilds into a Puzzle via
    /// `CreatorCodec.rebuild(_:)`.
    private struct Response: Decodable {
        let date: String
        let level: Int
        let difficulty: Double?
        let doc: CreatorPuzzleDoc
    }

    /// Fetch today's (or a specified day's) daily puzzle. Uses the
    /// cached value if one exists for this date. `nonisolated` so
    /// the detached generator task can call us without bouncing
    /// through the main actor.
    nonisolated static func fetch(for date: String) async -> (puzzle: Puzzle, level: Int)? {
        // Cache hit short-circuit.
        if let cached = readCache(date: date),
           let puz = CreatorCodec.rebuild(cached.doc) {
            return (puz, cached.level)
        }
        guard var comps = URLComponents(string: "https://kroma.ianhandy.com/api/daily") else {
            return nil
        }
        comps.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let puz = CreatorCodec.rebuild(decoded.doc, level: decoded.level) else {
                return nil
            }
            writeCache(date: date, level: decoded.level, doc: decoded.doc)
            return (puz, decoded.level)
        } catch {
            return nil
        }
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        let date: String
        let level: Int
        let doc: CreatorPuzzleDoc
    }

    private nonisolated static func readCache(date: String) -> CacheEntry? {
        let key = cacheKeyPrefix + date
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    private nonisolated static func writeCache(date: String, level: Int, doc: CreatorPuzzleDoc) {
        let key = cacheKeyPrefix + date
        let entry = CacheEntry(date: date, level: level, doc: doc)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: key)
        // Opportunistic GC: drop every other kroma.daily.cache.* key so
        // the defaults plist doesn't keep growing. Keeps just today's
        // entry around.
        let all = UserDefaults.standard.dictionaryRepresentation().keys
        for k in all where k.hasPrefix(cacheKeyPrefix) && k != key {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }
}
