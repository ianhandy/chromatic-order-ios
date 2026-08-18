import Foundation

struct StreakLeaderboardEntry: Codable, Identifiable {
    let rank: Int
    let handle: String
    let longestStreak: Int

    var id: Int { rank }
}

enum StreakLeaderboardStore {
    private static let sharingKey = "kromaShareDailyStreak_v1"
    private static let endpoint = URL(string: "https://kroma.ianhandy.com/api/streaks")!

    private struct Feed: Decodable { let entries: [StreakLeaderboardEntry] }
    private struct Submission: Encodable {
        let playerId: String
        let longestStreak: Int
        let completedThrough: String
    }
    private struct Identity: Encodable { let playerId: String }

    static var isSharing: Bool {
        UserDefaults.standard.bool(forKey: sharingKey)
    }

    static func fetch(limit: Int = 50) async throws -> [StreakLeaderboardEntry] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Feed.self, from: data).entries
    }

    static func setSharing(_ enabled: Bool, summary: DailyStreakSummary) async -> Bool {
        if enabled {
            if summary.longest > 0, !(await submit(summary)) { return false }
            UserDefaults.standard.set(true, forKey: sharingKey)
            return true
        }

        guard await removeRemoteRecord() else { return false }
        UserDefaults.standard.set(false, forKey: sharingKey)
        return true
    }

    static func submitIfEnabled(_ summary: DailyStreakSummary) async {
        guard isSharing else { return }
        _ = await submit(summary)
    }

    private static func submit(_ summary: DailyStreakSummary) async -> Bool {
        guard summary.longest > 0, let completedThrough = summary.completedThrough else {
            return true
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONEncoder().encode(Submission(
            playerId: CommunityStore.voterId,
            longestStreak: summary.longest,
            completedThrough: completedThrough
        ))
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    private static func removeRemoteRecord() async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONEncoder().encode(Identity(playerId: CommunityStore.voterId))
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}
