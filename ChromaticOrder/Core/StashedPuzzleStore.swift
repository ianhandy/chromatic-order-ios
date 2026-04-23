//  On-disk cache for generated puzzles whose computed difficulty
//  didn't match the level the generator was asked for. Harder-than-
//  needed layouts get stashed here at their actual difficulty; when
//  the player later reaches that level, `pop(difficulty:)` returns a
//  ready-made puzzle instead of paying the RNG cost again.
//
//  Easier-than-needed layouts are simply discarded by the caller —
//  they were strictly worse than "generate again" so stashing them
//  would pollute the ledger with stale, off-tier puzzles.

import Foundation

/// Keys are difficulty values as strings (`"3"`, `"7"`, …) because
/// UserDefaults plist dictionaries don't accept non-String keys.
/// Storage layout: `[difficulty: [puzzle-json]]`.
private let stashedPuzzlesKey = "kromaStashedPuzzles_v1"

/// Upper bound on how many puzzles we keep per difficulty bucket.
/// The same difficulty appearing twice is fine; beyond this we drop
/// the oldest so a hot RNG run can't balloon the persistent store.
private let perBucketLimit = 3

enum StashedPuzzleStore {
    /// Append a JSON-encoded puzzle to the bucket for `difficulty`.
    /// FIFO eviction at `perBucketLimit`.
    nonisolated static func stash(puzzleJSON: String, difficulty: Int) {
        var dict = load()
        let key = String(difficulty)
        var list = dict[key] ?? []
        list.append(puzzleJSON)
        if list.count > perBucketLimit {
            list.removeFirst(list.count - perBucketLimit)
        }
        dict[key] = list
        save(dict)
    }

    /// Remove + return the oldest puzzle stashed at `difficulty`.
    /// Returns nil when the bucket is empty.
    nonisolated static func pop(difficulty: Int) -> String? {
        var dict = load()
        let key = String(difficulty)
        guard var list = dict[key], !list.isEmpty else { return nil }
        let json = list.removeFirst()
        if list.isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = list
        }
        save(dict)
        return json
    }

    /// Drop every bucket whose difficulty is strictly below the given
    /// threshold — those puzzles are stale because the player has
    /// already climbed past that level. Called each time a puzzle is
    /// requested so the ledger can't grow indefinitely from below.
    nonisolated static func purgeBelow(difficulty: Int) {
        var dict = load()
        var changed = false
        for key in dict.keys {
            if let d = Int(key), d < difficulty {
                dict.removeValue(forKey: key)
                changed = true
            }
        }
        if changed { save(dict) }
    }

    // MARK: – Persistence

    private static func load() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: stashedPuzzlesKey) as? [String: [String]] ?? [:]
    }

    private static func save(_ dict: [String: [String]]) {
        UserDefaults.standard.set(dict, forKey: stashedPuzzlesKey)
    }
}
