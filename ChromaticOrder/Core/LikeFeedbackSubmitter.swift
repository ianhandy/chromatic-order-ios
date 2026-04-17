//  Quick like / dislike feedback — one-tap widget on the puzzle
//  screen. Writes to a separate Google Form so reactions live in
//  their own sheet.
//
//  The payload now includes the full puzzle JSON + metadata so liked
//  layouts can be replayed to other players later. Metadata field IDs
//  are placeholders until the dev sends a fresh pre-filled URL from
//  the expanded form; missing IDs silently skip that field in the
//  POST body so the build is green in the interim.

import Foundation

struct LikePayload {
    let liked: Bool
    let level: Int
    let generatorDifficulty: Int
    let channels: String
    let primaryChannel: String
    let grid: String
    let mode: String
    let cbMode: String
    /// JSON-serialized puzzle — layout + per-cell lock state + colors,
    /// produced by CreatorCodec.encodePuzzle. Large enough to belong
    /// in a Paragraph field, not a Short answer.
    let puzzleJSON: String
}

enum LikeFeedbackSubmitter {
    private static let formID =
        "1FAIpQLScmNYufpNOx0bXveICuyYm6vp1daOax9aA-zpKGg6RkHBH86Q"

    private enum F {
        static let liked           = "entry.1322490510"
        // Populated when the dev adds the 8 new fields to the form and
        // sends over a fresh pre-filled URL. Empty = skip in POST body.
        static let level           = ""
        static let generatorDiff   = ""
        static let channels        = ""
        static let primaryChannel  = ""
        static let grid            = ""
        static let mode            = ""
        static let cbMode          = ""
        static let puzzleJSON      = ""
    }

    static func submit(_ payload: LikePayload) async {
        guard !formID.isEmpty, !F.liked.isEmpty else { return }
        let url = URL(string: "https://docs.google.com/forms/d/e/\(formID)/formResponse")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("ChromaticOrder/iOS", forHTTPHeaderField: "User-Agent")

        var items: [URLQueryItem] = [
            URLQueryItem(name: F.liked, value: payload.liked ? "Like" : "Dislike"),
        ]
        // Conditional append — same pattern as FeedbackSubmitter. The
        // main Like/Dislike choice is the only REQUIRED field in the
        // form, so the submission lands regardless of whether metadata
        // fields are wired yet.
        func add(_ id: String, _ value: String) {
            if id.isEmpty { return }
            items.append(URLQueryItem(name: id, value: value))
        }
        add(F.level, "\(payload.level)")
        add(F.generatorDiff, "\(payload.generatorDifficulty)")
        add(F.channels, payload.channels)
        add(F.primaryChannel, payload.primaryChannel)
        add(F.grid, payload.grid)
        add(F.mode, payload.mode)
        add(F.cbMode, payload.cbMode)
        add(F.puzzleJSON, payload.puzzleJSON)

        var comps = URLComponents()
        comps.queryItems = items
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        // Fire-and-forget. Worst case: a vote goes unlogged. Never
        // worth blocking the UI.
        _ = try? await URLSession.shared.data(for: req)
    }
}
