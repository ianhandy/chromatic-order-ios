import Foundation

/// Exact, local-only checkpoint of the board currently in play. This is
/// intentionally separate from progression/iCloud: a half-solved board is a
/// transient device session, while unlocks and stats are durable account data.
enum InProgressSessionStore {
    static let key = "kromaInProgressSession_v1"

    struct ColorValue: Codable {
        let L: Double
        let c: Double
        let h: Double

        init(_ color: OKLCh) {
            L = color.L
            c = color.c
            h = color.h
        }

        var color: OKLCh { OKLCh(L: L, c: c, h: h) }
    }

    struct Placement: Codable {
        let r: Int
        let c: Int
        let color: ColorValue
    }

    struct Snapshot: Codable {
        let version: Int
        var autoResume: Bool
        let savedAt: Date
        let puzzleJSON: String
        let placements: [Placement]
        let bank: [ColorValue?]
        let mode: String
        let level: Int
        let checks: Int
        let challengeSolveCount: Int
        let challengeBonusLevels: Int
        let consecutiveNoHeartSolves: Int
        let consecutivePerfectSolves: Int
        let heartLostThisLevel: Bool
        let campaignIndex: Int?
        let dailyDateKey: String?
        let cameFromGallery: Bool
        let galleryPuzzleID: String?
        let galleryCollectionID: String?
        let favoritePath: String?
        let customTitle: String?
        let elapsedSeconds: Int
        let mistakeCount: Int
        let moveCount: Int
        let showedIncorrect: Bool
        let showIncorrect: Bool
        let engagedThisLevel: Bool
        let solved: Bool?
        let usedHint: Bool
        let hintStage: Int
        let hintGradientID: Int?
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(Snapshot.self, from: data),
              value.version == 1 else { return nil }
        return value
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func setAutoResume(_ autoResume: Bool) {
        guard var snapshot = load() else { return }
        snapshot.autoResume = autoResume
        save(snapshot)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
