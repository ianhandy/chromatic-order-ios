//  Persistent player statistics. Updated on every solve; surfaced in
//  Views/StatsView. Scope is deliberately narrow: a few meaningful
//  numbers so the screen doesn't become a data wall, but enough that a
//  returning player sees their progress at a glance.

import Foundation

struct Stats: Codable {
    var totalSolves: Int = 0
    var zenSolves: Int = 0
    var challengeSolves: Int = 0
    var dailySolves: Int = 0
    /// Best challenge-mode cumulative score ever reached. Separate
    /// from the session `score` in GameState — this is the
    /// high-water mark across runs.
    var bestChallengeScore: Int = 0
    /// Current consecutive-solves-with-zero-mistakes count. Reset on
    /// any mistake or "show incorrect" peek.
    var currentCleanStreak: Int = 0
    /// Longest `currentCleanStreak` ever reached.
    var longestCleanStreak: Int = 0
    /// Cumulative puzzle-solve seconds.
    var totalSolveSeconds: Int = 0
    /// Set of CB mode raw values the player has solved at least one
    /// puzzle under. Stored as an array for Codable; deduped on load.
    var cbModesSeen: [String] = []
}

enum StatsStore {
    private static let key = "kromaStats_v1"

    static func load() -> Stats {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Stats.self, from: data) else {
            return Stats()
        }
        return s
    }

    static func save(_ s: Stats) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
            CloudSync.push(key)
        }
    }

    /// Record a solve. `clean` = no mistakes, no "show incorrect" peek.
    /// `mode`: zen / challenge / daily. `cbMode`: raw-value string so
    /// we don't import CBMode here and widen the module graph.
    static func recordSolve(
        mode: String,
        clean: Bool,
        solveSeconds: Int,
        cbMode: String,
        challengeScore: Int? = nil
    ) {
        var s = load()
        s.totalSolves += 1
        switch mode {
        case "zen": s.zenSolves += 1
        case "challenge": s.challengeSolves += 1
        case "daily": s.dailySolves += 1
        default: break
        }
        s.totalSolveSeconds += max(0, solveSeconds)
        if clean {
            s.currentCleanStreak += 1
            if s.currentCleanStreak > s.longestCleanStreak {
                s.longestCleanStreak = s.currentCleanStreak
            }
        } else {
            s.currentCleanStreak = 0
        }
        if let cs = challengeScore, cs > s.bestChallengeScore {
            s.bestChallengeScore = cs
        }
        if !s.cbModesSeen.contains(cbMode) {
            s.cbModesSeen.append(cbMode)
        }
        save(s)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
