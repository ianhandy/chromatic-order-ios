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
    private static let bookmarksKey = "kromaCampaignBookmarks_v1"
    private static let recentKey = "kromaCampaignRecent_v1"

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

    /// Every chapter begins as a replayable entry point. Within a chapter,
    /// a level opens once it or its immediately preceding level is cleared.
    static func isUnlocked(_ index: Int) -> Bool {
        guard let chapter = CampaignCatalog.chapter(containing: index) else {
            return false
        }
        return index == chapter.first || isCleared(index) || isCleared(index - 1)
    }

    /// Compact Explore labels count levels within their chapter, not across
    /// the whole campaign.
    static func localNumber(for index: Int) -> Int? {
        guard let chapter = CampaignCatalog.chapter(containing: index) else {
            return nil
        }
        return index - chapter.first + 1
    }

    static func chapterCompletion(_ chapter: CampaignChapter) -> Int {
        chapter.levelRange.reduce(into: 0) { count, index in
            if isCleared(index) { count += 1 }
        }
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

    // ─── Quick access ──────────────────────────────────────────────

    static var bookmarks: [Int] {
        (UserDefaults.standard.array(forKey: bookmarksKey) as? [Int] ?? [])
            .filter { CampaignCatalog.level($0) != nil }
            .sorted()
    }

    static func isBookmarked(_ index: Int) -> Bool {
        bookmarks.contains(index)
    }

    static func toggleBookmark(_ index: Int) {
        guard CampaignCatalog.level(index) != nil else { return }
        var set = Set(bookmarks)
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
        UserDefaults.standard.set(Array(set).sorted(), forKey: bookmarksKey)
    }

    /// Most-recent first, deduplicated and bounded so the picker stays quiet.
    static var recent: [Int] {
        (UserDefaults.standard.array(forKey: recentKey) as? [Int] ?? [])
            .filter { CampaignCatalog.level($0) != nil }
    }

    static func recordPlayed(_ index: Int) {
        guard CampaignCatalog.level(index) != nil else { return }
        var values = recent.filter { $0 != index }
        values.insert(index, at: 0)
        UserDefaults.standard.set(Array(values.prefix(8)), forKey: recentKey)
        lastPlayed = index
    }

    /// Debug/reset path — also used by the Options "reset progress" flow.
    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: clearedKey)
        UserDefaults.standard.removeObject(forKey: tipsKey)
        UserDefaults.standard.removeObject(forKey: lastPlayedKey)
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
        UserDefaults.standard.removeObject(forKey: recentKey)
    }
}
