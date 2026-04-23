//  Ring buffer of recently-solved puzzle fingerprints. The generator
//  consults this to avoid handing the player a puzzle they've already
//  completed. Fingerprints include grid size + gradient positions, so
//  only structurally identical layouts are rejected — same shape at a
//  different grid position is still considered fresh.
//
//  Persisted in UserDefaults; FIFO eviction at `capacity`.

import Foundation

private let defaultsKey = "kromaSolvedPuzzleFingerprints_v1"
private let capacity = 200

enum SolvedPuzzleHistory {
    /// Record a solved puzzle's fingerprint. Call after every solve.
    nonisolated static func push(_ fingerprint: String) {
        var list = load()
        list.append(fingerprint)
        if list.count > capacity {
            list.removeFirst(list.count - capacity)
        }
        UserDefaults.standard.set(list, forKey: defaultsKey)
    }

    /// True when the fingerprint matches a previously-solved puzzle.
    nonisolated static func contains(_ fingerprint: String) -> Bool {
        load().contains(fingerprint)
    }

    private static func load() -> [String] {
        (UserDefaults.standard.array(forKey: defaultsKey) as? [String]) ?? []
    }
}
