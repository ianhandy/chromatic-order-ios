//  FIFO set of community-pool puzzle IDs the player has been served
//  from `/api/liked/random`. The community injection path consults
//  this (in GameState.swift) to skip puzzles the player has already
//  received, so a popular puzzle served on day 1 won't reappear on
//  day 14. Unlike the daily-shape gate, this is lifetime per install —
//  a puzzle you've seen from the community pool never rotates back in
//  unless you reinstall.
//
//  Persisted in UserDefaults as a string array. FIFO-capped at
//  `capacity` entries so long-term play doesn't grow the cache
//  unboundedly. 2000 is well past any realistic played-count while
//  still being tiny on disk.

import Foundation

private let defaultsKey = "kromaCommunitySeenIds_v1"
private let capacity = 2000

enum CommunitySeenIds {
    /// Same XCTest short-circuit `ShapesSeenToday` uses — audit runs
    /// don't hit the live community endpoint, but callers may still
    /// check membership, so return false + no-op writes.
    nonisolated static var isUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Record a community-puzzle ID as seen by this install.
    nonisolated static func push(_ id: String) {
        if isUnderTest { return }
        guard !id.isEmpty else { return }
        var list = load()
        list.append(id)
        if list.count > capacity {
            list.removeFirst(list.count - capacity)
        }
        UserDefaults.standard.set(list, forKey: defaultsKey)
    }

    /// True when the ID appears in the seen ledger.
    nonisolated static func contains(_ id: String) -> Bool {
        if isUnderTest { return false }
        guard !id.isEmpty else { return false }
        return load().contains(id)
    }

    private static func load() -> [String] {
        (UserDefaults.standard.array(forKey: defaultsKey) as? [String]) ?? []
    }
}
