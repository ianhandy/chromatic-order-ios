//  Quick like / dislike feedback — one-tap widget on the puzzle
//  screen. Lighter than the full feedback sheet; drops a single-row
//  POST to a separate one-question Google Form so the data lives
//  in its own sheet (no joins with the rated-feedback stream).
//
//  Form URL + field ID are placeholders until the dev sends a
//  pre-filled URL from the new form. Submission silently no-ops
//  until the placeholder is replaced, so the widget works locally
//  even before the form is live.

import Foundation

enum LikeFeedbackSubmitter {
    /// The Kroma Level Like form (separate from the main feedback form
    /// so reactions live in their own sheet, no joins needed).
    private static let formID: String =
        "1FAIpQLScmNYufpNOx0bXveICuyYm6vp1daOax9aA-zpKGg6RkHBH86Q"

    /// Entry ID for the one-choice question. Values must match the
    /// form's Multiple choice options exactly: "Like" or "Dislike".
    private static let fieldID: String = "entry.1322490510"

    static func submit(_ liked: Bool) async {
        guard !formID.isEmpty, !fieldID.isEmpty else {
            // Placeholder — no form wired yet. No-op so the widget's
            // local state still toggles and the player gets UI feedback.
            return
        }
        let url = URL(string: "https://docs.google.com/forms/d/e/\(formID)/formResponse")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("ChromaticOrder/iOS", forHTTPHeaderField: "User-Agent")

        var comps = URLComponents()
        comps.queryItems = [URLQueryItem(name: fieldID, value: liked ? "Like" : "Dislike")]
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        // Fire-and-forget — the widget updates locally whether or not
        // the POST lands. Worst case: a tap goes unlogged. Never worth
        // blocking the UI with retries.
        _ = try? await URLSession.shared.data(for: req)
    }
}
