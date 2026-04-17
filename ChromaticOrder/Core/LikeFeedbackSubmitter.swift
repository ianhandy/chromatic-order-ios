//  Quick like/dislike feedback — one-tap widget. Writes to a separate
//  Google Form so reactions live in their own sheet.
//
//  Payload is minimal on purpose: the Like/Dislike choice + a single
//  JSON blob that carries the puzzle AND the session context (level,
//  mode, CB mode). Everything else — difficulty, channels, grid size —
//  is derivable from the JSON on the analysis side, so no need for
//  redundant flat columns.

import Foundation

struct LikePayload {
    let liked: Bool
    /// JSON blob encoded by CreatorCodec.encodePuzzleWithSession:
    /// puzzle structure + per-cell locks + difficulty + level + mode +
    /// cbMode. Large — belongs in a Paragraph field, not Short answer.
    let json: String
}

enum LikeFeedbackSubmitter {
    private static let formID =
        "1FAIpQLScmNYufpNOx0bXveICuyYm6vp1daOax9aA-zpKGg6RkHBH86Q"

    private enum F {
        static let liked = "entry.1322490510"
        /// Placeholder — populated once the dev adds a single Paragraph
        /// field to the Like form and sends a fresh pre-filled URL.
        /// Empty string = skip in POST body (the Like/Dislike choice
        /// submits successfully on its own in the meantime).
        static let json = ""
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
        if !F.json.isEmpty {
            items.append(URLQueryItem(name: F.json, value: payload.json))
        }

        var comps = URLComponents()
        comps.queryItems = items
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        _ = try? await URLSession.shared.data(for: req)
    }
}
