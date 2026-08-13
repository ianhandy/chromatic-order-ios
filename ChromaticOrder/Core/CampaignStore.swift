//  Campaign progress. Two facts per install: which levels are cleared, and
//  which tips have been shown. Levels unlock one at a time so the teaching
//  order actually holds — you can replay anything you've cleared.
//
//  Deliberately independent of zen/challenge progression: the campaign is
//  the on-ramp, and clearing it doesn't hand out challenge levels.

import Foundation

enum CampaignStore {
    private static let clearedKey = "kromaCampaignCleared_v1"
    private static let tipsKey = "kromaCampaignTipsSeen_v1"
    private static let lastPlayedKey = "kromaCampaignLastPlayed_v1"

    // ─── Cleared levels ────────────────────────────────────────────

    static func cleared() -> Set<Int> {
        let raw = UserDefaults.standard.array(forKey: clearedKey) as? [Int] ?? []
        return Set(raw)
    }

    static func isCleared(_ index: Int) -> Bool {
        cleared().contains(index)
    }

    static func markCleared(_ index: Int) {
        var set = cleared()
        guard !set.contains(index) else { return }
        set.insert(index)
        UserDefaults.standard.set(Array(set).sorted(), forKey: clearedKey)
    }

    /// Highest cleared level, 0 when the player hasn't finished one yet.
    static var highestCleared: Int { cleared().max() ?? 0 }

    /// A level is open if it's the first, already cleared, or the one right
    /// after the player's furthest clear. Replaying is always allowed;
    /// skipping ahead isn't, because each level leans on the last.
    static func isUnlocked(_ index: Int) -> Bool {
        index <= 1 || isCleared(index) || isCleared(index - 1)
    }

    /// Where "continue" should drop the player: the first level they
    /// haven't cleared, or the last level once the campaign is finished.
    static var nextUp: Int {
        let cleared = cleared()
        for i in 1...max(1, CampaignCatalog.count) where !cleared.contains(i) {
            return i
        }
        return CampaignCatalog.count
    }

    static var isComplete: Bool {
        CampaignCatalog.count > 0 && cleared().count >= CampaignCatalog.count
    }

    static var clearedCount: Int { cleared().count }

    // ─── Tips ──────────────────────────────────────────────────────

    static func hasSeenTip(_ index: Int) -> Bool {
        let raw = UserDefaults.standard.array(forKey: tipsKey) as? [Int] ?? []
        return raw.contains(index)
    }

    static func markTipSeen(_ index: Int) {
        var raw = UserDefaults.standard.array(forKey: tipsKey) as? [Int] ?? []
        guard !raw.contains(index) else { return }
        raw.append(index)
        UserDefaults.standard.set(raw, forKey: tipsKey)
    }

    // ─── Resume ────────────────────────────────────────────────────

    static var lastPlayed: Int {
        get { UserDefaults.standard.integer(forKey: lastPlayedKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastPlayedKey) }
    }

    /// Debug/reset path — also used by the Options "reset progress" flow.
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: clearedKey)
        UserDefaults.standard.removeObject(forKey: tipsKey)
        UserDefaults.standard.removeObject(forKey: lastPlayedKey)
    }
}
