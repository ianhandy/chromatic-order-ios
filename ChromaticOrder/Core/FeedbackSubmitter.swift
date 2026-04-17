//  Google Forms feedback submission. POSTs form-urlencoded body to
//  /formResponse — no auth required, no CORS hurdles from a native
//  app. Field IDs extracted from a pre-filled form URL; when the form
//  schema changes, update the `fields` dict and that's it.
//
//  Form URL:
//  https://docs.google.com/forms/d/e/1FAIpQLSdFnnAS3Cys-kqo8tvhhOFvT1BMY9nokMT8ups0ZfPtF4d_IA/viewform

import Foundation

struct FeedbackPayload {
    let difficulty: Int
    let quality: Int
    let notes: String
    let appVersion: String
    let device: String
    let level: Int
    let mode: String
    let generatorDifficulty: Int
    let channels: String
    let primaryChannel: String
    let grid: String
    let gradientCount: Int
    let bankSize: Int
    let pairProx: Double
    let extrapProx: Double
    let interDist: Double
    let gradientMetrics: String
    let reduceMotion: Bool
    // Added round 2: play-session diagnostics. All four are per-puzzle,
    // reset on startLevel.
    let completed: Bool
    let timeSpentSec: Int
    let mistakes: Int
    let cbMode: String
}

enum FeedbackSubmitter {
    /// Submit to the live Google Form. Returns on successful POST
    /// (HTTP 200); throws if the network is down or Google rejects
    /// the request. Google responds 200 with a 'thank you' HTML page
    /// on success regardless of whether every field matched — we
    /// treat the 200 as ground truth and don't parse the body.
    static func submit(_ payload: FeedbackPayload) async throws {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("ChromaticOrder/iOS",
                     forHTTPHeaderField: "User-Agent")
        req.httpBody = encodedBody(payload).data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SubmitError.invalidResponse
        }
        // Google sometimes 302s to a confirmation page; both 200 and
        // 302 mean the submission was accepted.
        guard (200..<400).contains(http.statusCode) else {
            throw SubmitError.badStatus(http.statusCode)
        }
    }

    enum SubmitError: LocalizedError {
        case invalidResponse
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Server returned an unexpected response."
            case .badStatus(let c): return "Submission failed (status \(c))."
            }
        }
    }

    // MARK: - Form metadata

    private static let formID =
        "1FAIpQLSdFnnAS3Cys-kqo8tvhhOFvT1BMY9nokMT8ups0ZfPtF4d_IA"

    private static var endpoint: URL {
        URL(string: "https://docs.google.com/forms/d/e/\(formID)/formResponse")!
    }

    /// Field IDs pulled from the pre-filled URL. Order here is the
    /// order of the URL-encoded body below (doesn't affect Google's
    /// parsing — entries are matched by ID, not position — but kept
    /// readable so a missing field is easy to spot).
    private enum F {
        static let difficulty        = "entry.566809603"
        static let quality           = "entry.482675444"
        static let notes             = "entry.256259279"
        static let appVersion        = "entry.1119642561"
        static let device            = "entry.2125523127"
        static let level             = "entry.1794778775"
        static let mode              = "entry.772512749"
        static let generatorDiff     = "entry.670606315"
        static let channels          = "entry.1766912962"
        static let primaryChannel    = "entry.1883586359"
        static let grid              = "entry.365752139"
        static let gradientCount     = "entry.1735876098"
        static let bankSize          = "entry.583724291"
        static let pairProx          = "entry.1993840396"
        static let extrapProx        = "entry.383571357"
        static let interDist         = "entry.128656299"
        static let gradientMetrics   = "entry.255574131"
        static let reduceMotion      = "entry.4622635"
        // Placeholder IDs — filled in once the dev adds Completed /
        // Time spent (s) / Mistakes / CB mode to the form and sends
        // over a fresh pre-filled URL. Empty string means "don't POST
        // this field" and the build stays green.
        static let completed         = ""
        static let timeSpentSec      = ""
        static let mistakes          = ""
        static let cbMode            = ""
    }

    private static func encodedBody(_ p: FeedbackPayload) -> String {
        var items: [URLQueryItem] = [
            URLQueryItem(name: F.difficulty, value: "\(p.difficulty)"),
            URLQueryItem(name: F.quality, value: "\(p.quality)"),
            URLQueryItem(name: F.notes, value: p.notes),
            URLQueryItem(name: F.appVersion, value: p.appVersion),
            URLQueryItem(name: F.device, value: p.device),
            URLQueryItem(name: F.level, value: "\(p.level)"),
            URLQueryItem(name: F.mode, value: p.mode),
            URLQueryItem(name: F.generatorDiff, value: "\(p.generatorDifficulty)"),
            URLQueryItem(name: F.channels, value: p.channels),
            URLQueryItem(name: F.primaryChannel, value: p.primaryChannel),
            URLQueryItem(name: F.grid, value: p.grid),
            URLQueryItem(name: F.gradientCount, value: "\(p.gradientCount)"),
            URLQueryItem(name: F.bankSize, value: "\(p.bankSize)"),
            URLQueryItem(name: F.pairProx, value: String(format: "%.2f", p.pairProx)),
            URLQueryItem(name: F.extrapProx, value: String(format: "%.2f", p.extrapProx)),
            URLQueryItem(name: F.interDist, value: String(format: "%.1f", p.interDist)),
            URLQueryItem(name: F.gradientMetrics, value: p.gradientMetrics),
            URLQueryItem(name: F.reduceMotion, value: p.reduceMotion ? "On" : "Off"),
        ]
        // Optional fields — only included once the form has entry IDs
        // for them. Skipping when the ID is empty keeps the POST body
        // clean and avoids a "entry.=value" no-op that Google Forms
        // would either ignore or error on.
        if !F.completed.isEmpty {
            items.append(URLQueryItem(name: F.completed, value: p.completed ? "true" : "false"))
        }
        if !F.timeSpentSec.isEmpty {
            items.append(URLQueryItem(name: F.timeSpentSec, value: "\(p.timeSpentSec)"))
        }
        if !F.mistakes.isEmpty {
            items.append(URLQueryItem(name: F.mistakes, value: "\(p.mistakes)"))
        }
        if !F.cbMode.isEmpty {
            items.append(URLQueryItem(name: F.cbMode, value: p.cbMode))
        }
        // Rebuild via URLComponents so every value is %-encoded the
        // way form POSTs expect (plus-as-space, special chars encoded).
        var comps = URLComponents()
        comps.queryItems = items
        return comps.percentEncodedQuery ?? ""
    }
}
