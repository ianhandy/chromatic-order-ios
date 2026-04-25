//  Client for the community-submitted-puzzles feature on the kroma
//  web backend. Covers:
//   • POST /api/community/submit    — send a Creator-built doc for review
//   • GET  /api/community/feed      — list approved puzzles
//   • POST /api/community/vote      — up/down/retract a vote
//
//  Voter identity — a stable UUID per device stored in Keychain so it
//  survives UserDefaults-based "Reset Progress" and app data clears.
//  Only reinstalling the app (which wipes the Keychain item with the
//  thisDeviceOnly accessibility class) generates a new voter. This is
//  the primary anti-abuse safeguard for voting; the admin moderation
//  queue is the trust boundary for submissions themselves.

import Foundation
import Security

/// Minimal typed model of the feed response. `doc` rides through as a
/// fully-decoded `CreatorPuzzleDoc` so callers can rebuild a playable
/// puzzle without a second parse.
struct CommunityPuzzleEntry: Identifiable, Codable {
    let id: String
    let doc: CreatorPuzzleDoc
    let level: Int
    let submitterName: String?
    // Mutable so the client can apply optimistic vote updates before
    // the server's recount lands. Overwritten by the server response
    // on success; rolled back to the captured snapshot on failure.
    var upCount: Int
    var downCount: Int
    var score: Int
    let approvedAt: Int?

    /// Local vote state layered on top of the server's counts.
    var myVote: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, doc, level, submitterName, upCount, downCount, score, approvedAt
    }
}

enum CommunitySort: String { case top, new }

enum CommunityStore {

    // MARK: - Endpoint base

    private static let apiBase = "https://kroma.ianhandy.com"

    // MARK: - Keychain-backed voter ID

    private static let voterIdService = "com.ianhandy.kroma"
    private static let voterIdAccount = "community.voterId.v1"

    /// Stable UUID attached to every vote POST. Lives in Keychain so
    /// UserDefaults-based resets don't wipe it — a determined user has
    /// to delete + reinstall to cycle identities.
    static var voterId: String {
        if let existing = readKeychain(
            service: voterIdService, account: voterIdAccount
        ), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        _ = writeKeychain(
            service: voterIdService, account: voterIdAccount, value: fresh
        )
        return fresh
    }

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:      kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    @discardableResult
    private static func writeKeychain(service: String, account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        // Delete any stale row first so we don't collide with a prior
        // write — simpler than branching on duplicate-item errors.
        let delQuery: [String: Any] = [
            kSecClass as String:      kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delQuery as CFDictionary)
        let addQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecValueData as String:    data,
            // thisDeviceOnly so a restored backup on a new device
            // shows up as a fresh voter — avoids cloning votes
            // across devices the user already owns.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Submit

    struct SubmitResponse: Decodable {
        let ok: Bool?
        let id: String?
        let status: String?   // "pending" | "approved" | "rejected"
        let throttled: Bool?
        let error: String?
    }

    /// Post a Creator-built puzzle doc to the moderation queue. Returns
    /// whatever the server had — on a duplicate (content-hash match),
    /// the server echoes the existing row's current status with
    /// `throttled: true` so the client can show "already pending" or
    /// "already approved" instead of another pending card.
    nonisolated static func submit(
        doc: CreatorPuzzleDoc,
        level: Int,
        submitterName: String?
    ) async -> Result<SubmitResponse, Error> {
        guard let url = URL(string: "\(apiBase)/api/community/submit") else {
            return .failure(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        let body: [String: Any] = [
            "doc": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(doc))) ?? [:],
            "level": level,
            "submitterName": submitterName ?? NSNull(),
            "installId": voterId,
        ]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch { return .failure(error) }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let decoded = (try? JSONDecoder().decode(SubmitResponse.self, from: data))
                ?? SubmitResponse(ok: nil, id: nil, status: nil, throttled: nil,
                                  error: "malformed response")
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(NSError(
                    domain: "CommunityStore", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "HTTP \(http.statusCode)"]
                ))
            }
            return .success(decoded)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Feed

    private struct FeedResponse: Decodable {
        let puzzles: [CommunityPuzzleEntry]
    }

    /// Fetch the public feed. Returns an empty list on any failure so
    /// the UI always has something to render — surfaces a separate
    /// error path via the boolean second tuple element.
    nonisolated static func fetchFeed(
        sort: CommunitySort = .top,
        limit: Int = 50
    ) async -> (entries: [CommunityPuzzleEntry], ok: Bool) {
        guard var comps = URLComponents(string: "\(apiBase)/api/community/feed") else {
            return ([], false)
        }
        comps.queryItems = [
            URLQueryItem(name: "sort", value: sort.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps.url else { return ([], false) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return ([], false)
            }
            let decoded = try JSONDecoder().decode(FeedResponse.self, from: data)
            return (decoded.puzzles, true)
        } catch {
            return ([], false)
        }
    }

    // MARK: - Vote

    struct VoteResponse: Decodable {
        let ok: Bool?
        let upCount: Int?
        let downCount: Int?
        let score: Int?
        let myVote: Int?
        let error: String?
    }

    // MARK: - Admin (dev menu)

    /// UserDefaults key for the admin token entered in the dev menu.
    /// Stored alongside the rest of the app's preferences (not in the
    /// Keychain) since it's developer-only and #if DEBUG-gated; no
    /// production user ever sees this surface.
    static let adminTokenKey = "kroma.dev.adminToken"

    private static func currentAdminToken() -> String? {
        let raw = UserDefaults.standard.string(forKey: adminTokenKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct AdminFeedResponse: Decodable {
        let puzzles: [CommunityPuzzleEntry]
    }

    /// Admin: list pending submissions (oldest first). Mirrors the
    /// public feed shape minus vote counts.
    nonisolated static func adminFetchPending(limit: Int = 100) async
        -> Result<[CommunityPuzzleEntry], Error> {
        guard let token = currentAdminToken() else {
            return .failure(NSError(
                domain: "CommunityStore", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "admin token not set"]))
        }
        guard var comps = URLComponents(string: "\(apiBase)/api/community/pending") else {
            return .failure(URLError(.badURL))
        }
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = comps.url else { return .failure(URLError(.badURL)) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(token, forHTTPHeaderField: "x-admin-token")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failure(URLError(.badServerResponse))
            }
            if http.statusCode == 401 {
                return .failure(NSError(
                    domain: "CommunityStore", code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "unauthorized — bad admin token"]))
            }
            guard http.statusCode == 200 else {
                return .failure(NSError(
                    domain: "CommunityStore", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
            }
            // Pending rows ship without vote counts; decode through a
            // permissive intermediate so missing fields default to 0.
            struct PendingRow: Decodable {
                let id: String
                let doc: CreatorPuzzleDoc
                let level: Int
                let submitterName: String?
                let createdAt: Int?
            }
            struct PendingResponse: Decodable { let puzzles: [PendingRow] }
            let decoded = try JSONDecoder().decode(PendingResponse.self, from: data)
            let entries = decoded.puzzles.map {
                CommunityPuzzleEntry(
                    id: $0.id, doc: $0.doc, level: $0.level,
                    submitterName: $0.submitterName,
                    upCount: 0, downCount: 0, score: 0,
                    approvedAt: $0.createdAt
                )
            }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    enum AdminAction: String { case approve, reject }

    struct AdminModerateResponse: Decodable {
        let ok: Bool?
        let id: String?
        let status: String?
    }

    /// Admin: approve or reject a community submission. Approving a
    /// `pending` row promotes it to the public feed; rejecting works
    /// on rows in any status — `approved` rows disappear from the
    /// feed when flipped to `rejected` (effectively a removal).
    nonisolated static func adminModerate(
        id: String, action: AdminAction
    ) async -> Result<AdminModerateResponse, Error> {
        guard let token = currentAdminToken() else {
            return .failure(NSError(
                domain: "CommunityStore", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "admin token not set"]))
        }
        guard let url = URL(string: "\(apiBase)/api/community/moderate") else {
            return .failure(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-admin-token")
        req.timeoutInterval = 8
        do {
            req.httpBody = try JSONSerialization.data(
                withJSONObject: ["id": id, "action": action.rawValue])
        } catch { return .failure(error) }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let decoded = (try? JSONDecoder().decode(AdminModerateResponse.self, from: data))
                ?? AdminModerateResponse(ok: nil, id: nil, status: nil)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(NSError(
                    domain: "CommunityStore", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
            }
            return .success(decoded)
        } catch {
            return .failure(error)
        }
    }

    /// Cast, change, or retract a vote. `vote ∈ {-1, 0, +1}` where 0
    /// retracts an existing vote.
    nonisolated static func vote(
        puzzleId: String,
        vote: Int
    ) async -> Result<VoteResponse, Error> {
        guard [-1, 0, 1].contains(vote) else {
            return .failure(NSError(
                domain: "CommunityStore", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "vote must be -1, 0, or 1"]
            ))
        }
        guard let url = URL(string: "\(apiBase)/api/community/vote") else {
            return .failure(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        let body: [String: Any] = [
            "puzzleId": puzzleId,
            "voterId": voterId,
            "vote": vote,
        ]
        do { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        catch { return .failure(error) }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let decoded = (try? JSONDecoder().decode(VoteResponse.self, from: data))
                ?? VoteResponse(ok: nil, upCount: nil, downCount: nil,
                                score: nil, myVote: nil, error: "malformed response")
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(NSError(
                    domain: "CommunityStore", code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: decoded.error ?? "HTTP \(http.statusCode)"]
                ))
            }
            return .success(decoded)
        } catch {
            return .failure(error)
        }
    }
}
