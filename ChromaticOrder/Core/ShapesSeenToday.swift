//  Set of puzzle shape fingerprints the player has seen today — any
//  time `generatePuzzle` returns a board to the UI. Resets on local
//  calendar-day rollover so a fresh day restores the full shape space.
//
//  Works alongside two existing gates:
//   • `SolvedPuzzleHistory` — lifetime ring, push on solve (200 entries)
//   • `recentShapes` in Generate.swift — session-local, 16 entries
//
//  The three form a layered filter: recent (tightest, session) → today
//  (mid, persistent across crashes but daily-bounded) → solved
//  (lifetime). Candidates matching any gate are rejected until the
//  generator falls back to its emergency phase.
//
//  Persisted as a UserDefaults dictionary `{ day, sigs }`. Unbounded
//  within a day — a heavy session rarely crosses ~100 unique
//  fingerprints, so ~10KB worst-case is fine.

import Foundation

private let defaultsKey = "kromaShapesSeenToday_v1"
private let dayField = "day"
private let sigsField = "sigs"

enum ShapesSeenToday {
    /// True when running inside XCTest. The audit suites generate
    /// 10k+ puzzles per test; an unbounded daily ledger would grow
    /// O(n) and every `contains` turns into a linear scan, so
    /// generation thrashes. Gate both entry points to keep audit
    /// runs bounded — production sessions never come close to the
    /// scale where the ledger would need eviction.
    nonisolated static var isUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Record a fingerprint as seen today. Lazily rolls the day key —
    /// a push on a new local day replaces yesterday's set.
    nonisolated static func push(_ fingerprint: String) {
        if isUnderTest { return }
        let today = currentDayKey()
        var sigs = sigsForToday(dayKey: today)
        sigs.append(fingerprint)
        UserDefaults.standard.set(
            [dayField: today, sigsField: sigs] as [String: Any],
            forKey: defaultsKey
        )
    }

    /// True when the fingerprint has already been handed out today.
    nonisolated static func contains(_ fingerprint: String) -> Bool {
        if isUnderTest { return false }
        return sigsForToday(dayKey: currentDayKey()).contains(fingerprint)
    }

    // MARK: – internals

    private static func currentDayKey() -> String {
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d",
                      comps.year ?? 1970,
                      comps.month ?? 1,
                      comps.day ?? 1)
    }

    private static func sigsForToday(dayKey: String) -> [String] {
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let storedDay = dict[dayField] as? String,
              storedDay == dayKey,
              let sigs = dict[sigsField] as? [String]
        else {
            return []
        }
        return sigs
    }
}
