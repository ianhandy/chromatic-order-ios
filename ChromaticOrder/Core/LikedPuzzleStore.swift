//  Local record of puzzles the player has liked, plus their
//  challenge-mode solve stats (time / moves / perfect-or-not) for
//  each solve that happened while the puzzle was saved here.
//
//  Persisted to UserDefaults as a single JSON blob. The store is
//  the client-side half of the "send liked levels to other players"
//  feature: when a player likes a puzzle we append it here AND fire
//  a best-effort submit to the server pool (see `submitRemote`).
//  When the server side exists, the submit endpoint will weight a
//  distribution feed by the puzzle's aggregate like count.
//
//  Server integration notes (NOT YET IMPLEMENTED):
//    POST /api/liked/submit   body: { json, level, likedAt }
//    GET  /api/liked/random   returns a weighted-random liked
//                              puzzle for another player to play
//  The server should:
//    • dedupe by puzzle JSON hash
//    • keep a liked-count per puzzle
//    • weight selection by (likedCount / totalLikes) when sampling
//    • gate behind a rate limit so repeat likes can't brigade

import Foundation

struct ChallengeSolveStat: Codable {
    let solvedAtEpoch: Double
    let timeSec: Int
    let moveCount: Int
    let wasPerfect: Bool
}

struct LikedPuzzleRecord: Codable, Identifiable {
    let id: String                 // stable UUID
    let puzzleJSON: String         // CreatorCodec.encodePuzzle output
    let level: Int
    let likedAtEpoch: Double
    /// Per-solve stats. Only challenge-mode solves are recorded —
    /// zen / daily solves aren't tracked here because their
    /// difficulty isn't comparable across the pool.
    var challengeStats: [ChallengeSolveStat]
}

/// Pulled out of the enum so `nonisolated` call sites
/// (`dislikedShapeSignaturesList`, `isShapeDisliked`) can reference
/// these without tripping the main-actor isolation check. The keys
/// are immutable constants, not shared state.
private let defaultsKey_LikedStore = "likedPuzzleRecords_v1"
private let installIdKey_LikedStore = "kromaInstallId_v1"
private let dislikeSignaturesKey_LikedStore = "kromaDislikedShapeSignatures_v1"
private let dislikeSignatureLimit_LikedStore = 50
/// Separate cache slot for shape signatures pulled from the server's
/// aggregate dislike feed — kept apart from the local ledger so a
/// local reset (unlike / re-like flow) doesn't wipe community data.
private let remoteDislikeSignaturesKey_LikedStore = "kromaRemoteDislikedShapeSignatures_v1"
private let lastRemoteDislikeFetchKey_LikedStore = "kromaLastRemoteDislikeFetchEpoch_v1"
/// Minimum seconds between remote refreshes. One hour is plenty —
/// dislike aggregates don't shift meaningfully on a faster cadence,
/// and batching one fetch per session is the real goal anyway.
private let remoteDislikeFetchIntervalSec_LikedStore: Double = 3600
/// Upper bound on how many remote signatures we hold in memory.
/// Guards against a pathological server dump yanking device RAM.
private let remoteDislikeSignatureLimit_LikedStore = 500

@MainActor
enum LikedPuzzleStore {
    private static var defaultsKey: String { defaultsKey_LikedStore }
    private static var installIdKey: String { installIdKey_LikedStore }

    /// Opaque stable UUID for this install. Generated once on first
    /// access and persisted in UserDefaults — attached to every
    /// like/dislike POST so the server can enforce its permanent
    /// per-install dedupe without seeing any player-identifiable
    /// info. Clearing app data resets it (treated as a new install).
    static var installId: String {
        if let existing = UserDefaults.standard.string(forKey: installIdKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIdKey)
        return fresh
    }

    /// All liked puzzle records, newest-first by liked timestamp.
    static func all() -> [LikedPuzzleRecord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([LikedPuzzleRecord].self, from: data)
        else { return [] }
        return records.sorted { $0.likedAtEpoch > $1.likedAtEpoch }
    }

    /// Record a like. Fires a best-effort remote submit so the
    /// server-side pool can count this like for peer distribution.
    static func like(puzzle: Puzzle, puzzleJSON: String, level: Int) {
        let record = LikedPuzzleRecord(
            id: UUID().uuidString,
            puzzleJSON: puzzleJSON,
            level: level,
            likedAtEpoch: Date().timeIntervalSince1970,
            challengeStats: []
        )
        var records = load()
        // Dedupe by JSON so replaying + re-liking the same puzzle
        // doesn't pile up. First-liked wins on id/timestamp; we
        // update stats in-place via `recordChallengeSolve`.
        if !records.contains(where: { $0.puzzleJSON == puzzleJSON }) {
            records.append(record)
            save(records)
        }
        Task.detached { await submitRemote(record: record) }
    }

    /// Append a challenge-mode solve stat to whichever liked record
    /// matches the supplied puzzle JSON. No-op when the player
    /// hasn't liked this particular puzzle (we only collect stats
    /// for puzzles in the liked pool — these are the ones other
    /// players will receive).
    static func recordChallengeSolve(puzzleJSON: String,
                                      timeSec: Int,
                                      moveCount: Int,
                                      wasPerfect: Bool) {
        var records = load()
        guard let idx = records.firstIndex(where: { $0.puzzleJSON == puzzleJSON })
        else { return }
        records[idx].challengeStats.append(
            ChallengeSolveStat(
                solvedAtEpoch: Date().timeIntervalSince1970,
                timeSec: timeSec,
                moveCount: moveCount,
                wasPerfect: wasPerfect
            )
        )
        save(records)
    }

    /// Remove a liked record. Used when the player un-favorites a
    /// puzzle (not wired to UI yet but ready for a future feed).
    static func unlike(puzzleJSON: String) {
        var records = load()
        records.removeAll { $0.puzzleJSON == puzzleJSON }
        save(records)
    }

    /// Record a dislike. Decrements the puzzle's community like
    /// count server-side (removing from the pool if the count hits
    /// zero) and logs the dislike to a separate `dislikes` table
    /// for generator tuning. Also appends the puzzle's coarse shape
    /// signature to a local ledger so the on-device generator can
    /// reject candidates whose geometry the player has already
    /// flagged.
    static func dislike(puzzleJSON: String, shapeSignature: String?, level: Int) {
        if let sig = shapeSignature, !sig.isEmpty {
            appendDislikeSignature(sig)
        }
        let id = UUID().uuidString
        let install = installId
        Task.detached {
            await submitDislikeRemote(
                recordId: id,
                puzzleJSON: puzzleJSON,
                level: level,
                installId: install
            )
        }
    }

    // MARK: – Disliked shape signatures (local feedback loop)

    /// Append a shape signature to the local dislike ledger. FIFO
    /// eviction at `dislikeSignatureLimit` keeps the set bounded so
    /// old dislikes don't permanently shrink the generator's output
    /// space.
    private static func appendDislikeSignature(_ sig: String) {
        var sigs = dislikedShapeSignaturesList()
        sigs.append(sig)
        if sigs.count > dislikeSignatureLimit_LikedStore {
            sigs.removeFirst(sigs.count - dislikeSignatureLimit_LikedStore)
        }
        UserDefaults.standard.set(sigs, forKey: dislikeSignaturesKey_LikedStore)
    }

    /// Ordered ledger of shape signatures the player has disliked —
    /// newest last. May contain duplicates; a shape that's been
    /// flagged multiple times still counts as one signature for
    /// lookup purposes (handled in `isShapeDisliked`).
    nonisolated static func dislikedShapeSignaturesList() -> [String] {
        (UserDefaults.standard.array(forKey: dislikeSignaturesKey_LikedStore) as? [String]) ?? []
    }

    /// True when the given shape signature appears in either the
    /// local dislike ledger or the remote community feed. Safe to
    /// call off the main actor — reads a snapshot from UserDefaults
    /// without touching shared state.
    nonisolated static func isShapeDisliked(_ sig: String) -> Bool {
        if dislikedShapeSignaturesList().contains(sig) { return true }
        return remoteDislikedShapeSignatureSet().contains(sig)
    }

    /// Set of shape signatures pulled from the server's aggregate
    /// dislike feed. Refreshed by `refreshRemoteDislikedSignatures`.
    nonisolated static func remoteDislikedShapeSignatureSet() -> Set<String> {
        let arr = (UserDefaults.standard.array(forKey: remoteDislikeSignaturesKey_LikedStore) as? [String]) ?? []
        return Set(arr)
    }

    /// Refresh the remote dislike ledger from the server. Rate-limited
    /// to once per `remoteDislikeFetchIntervalSec` so frequent app
    /// resumes don't hammer the endpoint. Silent no-op on network
    /// failure — generator falls back to the local-only ledger.
    ///
    /// Server contract: `GET /api/liked/disliked_signatures`
    ///   Response: `{ "signatures": ["h3|v3", "h4|v4|v4", …] }`
    /// Server should aggregate dislikes across all installs, drop
    /// signatures below a small quorum threshold (e.g. ≥ 3 dislikes
    /// from distinct installs) so one player's taste doesn't poison
    /// the feed, and return the top ~500 entries sorted by dislike
    /// count. Client trusts the server's filtering — it just merges
    /// the payload into its local reject set.
    nonisolated static func refreshRemoteDislikedSignatures() async {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastRemoteDislikeFetchKey_LikedStore)
        if last > 0, now - last < remoteDislikeFetchIntervalSec_LikedStore {
            return
        }
        guard let url = URL(string: "https://kroma.ianhandy.com/api/liked/disliked_signatures") else {
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return
            }
            struct RemoteResponse: Decodable {
                let signatures: [String]
            }
            let decoded = try JSONDecoder().decode(RemoteResponse.self, from: data)
            let capped = Array(decoded.signatures.prefix(remoteDislikeSignatureLimit_LikedStore))
            UserDefaults.standard.set(capped, forKey: remoteDislikeSignaturesKey_LikedStore)
            UserDefaults.standard.set(now, forKey: lastRemoteDislikeFetchKey_LikedStore)
        } catch {
            // Swallow — leaves the existing cache in place so the
            // generator keeps benefitting from the last successful
            // fetch until the next refresh.
        }
    }

    // MARK: – Persistence

    private static func load() -> [LikedPuzzleRecord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([LikedPuzzleRecord].self, from: data)
        else { return [] }
        return records
    }

    private static func save(_ records: [LikedPuzzleRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: – Remote submission (stubbed)

    /// Best-effort upload of a liked puzzle to the server pool.
    /// Silently no-ops on network failure — the local record stays
    /// either way.
    private static func submitRemote(record: LikedPuzzleRecord) async {
        let install = Self.installId
        guard let url = URL(string: "https://kroma.ianhandy.com/api/liked/submit") else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5
        let body: [String: Any] = [
            "json": record.puzzleJSON,
            "level": record.level,
            "likedAtEpoch": record.likedAtEpoch,
            "installId": install,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Post a dislike to the server. Server-side: decrements the
    /// puzzle's like_count (removing the row at 0) and logs the
    /// dislike to the `dislikes` table for generator tuning.
    private static func submitDislikeRemote(recordId: String,
                                             puzzleJSON: String,
                                             level: Int,
                                             installId: String) async {
        guard let url = URL(string: "https://kroma.ianhandy.com/api/liked/dislike") else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5
        let body: [String: Any] = [
            "json": puzzleJSON,
            "level": level,
            "dislikedAtEpoch": Date().timeIntervalSince1970,
            "installId": installId,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Fetch a weighted-random liked puzzle from the community pool,
    /// optionally filtered to a specific challenge level. Returns
    /// nil on 404 (empty pool) or any network / decode error — the
    /// generator path will then fall through to local generation.
    /// Marked `nonisolated` so the detached generator task can call
    /// it without bouncing through the main actor — no shared state
    /// is touched here, only URL machinery and a JSON decode.
    nonisolated static func fetchCommunityRandom(level: Int?) async -> (json: String, level: Int)? {
        var comps = URLComponents(string: "https://kroma.ianhandy.com/api/liked/random")
        if let level {
            comps?.queryItems = [URLQueryItem(name: "level", value: String(level))]
        }
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            struct RandomResponse: Decodable {
                let id: String
                let json: String
                let level: Int
                let likeCount: Int
            }
            let decoded = try JSONDecoder().decode(RandomResponse.self, from: data)
            return (decoded.json, decoded.level)
        } catch {
            return nil
        }
    }
}
