//  The intro campaign: 100 hand-authored levels shipped in the bundle as
//  `campaign.json`. Each level is a named shape drawn out of gradients —
//  "Tee", "Anchor", "Mandala" — that teaches one more thing about reading
//  a ramp than the level before it.
//
//  Authored by tools/campaign/ in this repo (ASCII art in shapes.py,
//  colours + starter cells solved by build.py). Every level in the file is
//  uniquely solvable by the same rules PuzzleSolver enforces; the test
//  target re-checks that against the real solver on every run, so a
//  regenerated campaign can't ship an ambiguous board.

import Foundation

struct CampaignChapter: Codable, Identifiable, Hashable {
    let title: String
    let first: Int
    let last: Int
    let blurb: String

    var id: String { title }
    var levelRange: ClosedRange<Int> { first...last }
    var count: Int { last - first + 1 }
}

struct CampaignLevel: Codable, Identifiable {
    /// 1-based position in the campaign.
    let index: Int
    /// One or two words: what the shape is.
    let name: String
    let chapter: String
    /// Coaching line shown the first time this level is opened. Only the
    /// levels that introduce something have one.
    let tip: String?
    let gradientCount: Int
    let cellCount: Int
    /// Swatches the player has to place.
    let bankCount: Int
    let doc: CreatorPuzzleDoc

    var id: Int { index }

    /// Identity is the position in the campaign — the doc it carries isn't
    /// hashable and doesn't need to be.
    static func == (lhs: CampaignLevel, rhs: CampaignLevel) -> Bool {
        lhs.index == rhs.index
    }

    /// Build the playable puzzle. Locks travel in the doc, so every player
    /// gets exactly the starter cells the level was validated with.
    func puzzle() -> Puzzle? {
        CreatorCodec.rebuild(doc, level: index)
    }
}

struct CampaignFile: Codable {
    let version: Int
    let chapters: [CampaignChapter]
    let levels: [CampaignLevel]
}

enum CampaignCatalog {
    /// Parsed once and held: 100 levels of JSON is ~170 KB, and the level
    /// picker wants random access to all of it.
    private static let file: CampaignFile? = {
        guard let url = Bundle.main.url(forResource: "campaign", withExtension: "json") else {
            assertionFailure("campaign.json missing from the bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CampaignFile.self, from: data)
        } catch {
            assertionFailure("campaign.json failed to decode: \(error)")
            return nil
        }
    }()

    static var chapters: [CampaignChapter] { file?.chapters ?? [] }
    static var levels: [CampaignLevel] { file?.levels ?? [] }
    static var count: Int { levels.count }

    /// Level at a 1-based index, or nil past the end of the campaign.
    static func level(_ index: Int) -> CampaignLevel? {
        guard index >= 1, index <= levels.count else { return nil }
        return levels[index - 1]
    }

    static func chapter(containing index: Int) -> CampaignChapter? {
        chapters.first { $0.levelRange.contains(index) }
    }

    static func levels(in chapter: CampaignChapter) -> [CampaignLevel] {
        levels.filter { chapter.levelRange.contains($0.index) }
    }
}
