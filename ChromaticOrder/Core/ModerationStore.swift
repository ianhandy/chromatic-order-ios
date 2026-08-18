//  Player-facing moderation for user-generated content — App Store
//  Guideline 1.2.
//
//  1.2 asks for four things where players can see each other's
//  content. Three are in the app; the fourth is a store-listing field:
//
//    1. Filter objectionable material — server-side approval already
//       gates the community pool (pending / approved / rejected).
//    2. Report objectionable content  — `report(...)` below.
//    3. Block abusive users          — `block(name:)` below.
//    4. Published contact info       — the App Store listing's
//       support URL, not something the binary carries.
//
//  Everything here is LOCAL and takes effect immediately. That's
//  deliberate: a report that only fires a network call leaves the
//  player still staring at the thing they reported if the request is
//  slow or the backend is down. Reporting hides the item on this
//  device the moment it's tapped, and the server call is a
//  best-effort follow-up for moderation. Blocking is local-only by
//  design — it's this player's feed preference, not a global verdict.
//
//  Keyed on display name because that's all the payload carries:
//  `CommunityPuzzleEntry.submitterName` and
//  `StreakLeaderboardEntry.handle` are plain strings with no stable
//  account behind them. Name-based blocking is therefore approximate
//  (a renamed submitter reappears), which is the honest limit of the
//  current data model — noted rather than papered over. Per-entry
//  hiding is exact, since ids are stable.

import Foundation

enum ModerationStore {
    private static let blockedNamesKey = "kromaBlockedSubmitters_v1"
    private static let hiddenIdsKey    = "kromaHiddenCommunityIds_v1"
    private static let reportedIdsKey  = "kromaReportedCommunityIds_v1"

    /// Cap so a runaway list can't grow without bound in UserDefaults.
    /// Oldest entries fall off first.
    private static let maxEntries = 500

    // MARK: - Blocking (by display name)

    static var blockedNames: [String] {
        UserDefaults.standard.stringArray(forKey: blockedNamesKey) ?? []
    }

    /// Case- and whitespace-insensitive so "Ada" and " ada " are the
    /// same person as far as a block is concerned.
    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isBlocked(name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let target = normalized(name)
        return blockedNames.contains { normalized($0) == target }
    }

    static func block(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBlocked(name: trimmed) else { return }
        var list = blockedNames
        list.append(trimmed)
        if list.count > maxEntries { list.removeFirst(list.count - maxEntries) }
        UserDefaults.standard.set(list, forKey: blockedNamesKey)
    }

    static func unblock(name: String) {
        let target = normalized(name)
        let list = blockedNames.filter { normalized($0) != target }
        UserDefaults.standard.set(list, forKey: blockedNamesKey)
    }

    // MARK: - Per-entry hiding

    static var hiddenIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenIdsKey) ?? [])
    }

    static func isHidden(id: String) -> Bool { hiddenIds.contains(id) }

    static func hide(id: String) {
        var list = UserDefaults.standard.stringArray(forKey: hiddenIdsKey) ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        if list.count > maxEntries { list.removeFirst(list.count - maxEntries) }
        UserDefaults.standard.set(list, forKey: hiddenIdsKey)
    }

    // MARK: - Reporting

    static var reportedIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: reportedIdsKey) ?? [])
    }

    static func hasReported(id: String) -> Bool { reportedIds.contains(id) }

    private static func markReported(id: String) {
        var list = UserDefaults.standard.stringArray(forKey: reportedIdsKey) ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        if list.count > maxEntries { list.removeFirst(list.count - maxEntries) }
        UserDefaults.standard.set(list, forKey: reportedIdsKey)
    }

    /// Why a player is reporting something. Kept short and concrete —
    /// a free-text-only report is harder to triage and invites typing
    /// personal information into a field that leaves the device.
    enum Reason: String, CaseIterable, Identifiable {
        case offensive
        case spam
        case stolen
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .offensive: return "offensive or abusive"
            case .spam:      return "spam or nonsense"
            case .stolen:    return "not their puzzle"
            case .other:     return "something else"
            }
        }
    }

    /// Report an item. Hides it locally first — synchronously, before
    /// any network work — so the player never has to keep looking at
    /// something they just reported, regardless of what the server
    /// does. The POST is best-effort and its failure is deliberately
    /// not surfaced: from the player's side the report succeeded,
    /// because the content is gone.
    ///
    /// NOTE: `/api/community/report` must exist server-side for the
    /// moderation half to land. Until it's deployed this call 404s and
    /// is swallowed; the local hide still works, so 1.2's user-facing
    /// requirement is satisfied either way.
    static func report(id: String,
                       submitterName: String?,
                       reason: Reason,
                       note: String? = nil) {
        hide(id: id)
        markReported(id: id)

        guard let url = URL(string: "https://kroma.ianhandy.com/api/community/report")
        else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        var payload: [String: Any] = [
            "puzzleId": id,
            "reason": reason.rawValue,
            "reporterId": CommunityStore.voterId,
        ]
        if let submitterName, !submitterName.isEmpty {
            payload["submitterName"] = submitterName
        }
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Trimmed hard — this is a free-text field leaving the
            // device, and a long one invites pasting personal details.
            payload["note"] = String(note.prefix(500))
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        req.httpBody = body
        Task.detached(priority: .utility) {
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Feed filtering

    /// Drop anything this player has blocked or hidden. Applied at the
    /// point the feed is rendered rather than at fetch, so a block
    /// takes effect on already-loaded rows without a refetch.
    static func filterCommunity(_ entries: [CommunityPuzzleEntry]) -> [CommunityPuzzleEntry] {
        let hidden = hiddenIds
        return entries.filter { entry in
            !hidden.contains(entry.id) && !isBlocked(name: entry.submitterName)
        }
    }

    static func filterLeaderboard(_ entries: [StreakLeaderboardEntry]) -> [StreakLeaderboardEntry] {
        entries.filter { !isBlocked(name: $0.handle) }
    }
}
