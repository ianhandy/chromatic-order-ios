//  On-disk store of player-created + received puzzles. Lives under
//  ~/Documents/kroma/ — the app's sandboxed Documents directory, so
//  files survive offloads and iCloud backups where enabled. Each
//  puzzle is a single .kroma JSON file with a timestamp-prefixed
//  filename; metadata (grid size, difficulty, gradient count) is
//  parsed from the JSON on read, no sidecar.

import Foundation

struct GalleryPuzzle: Identifiable {
    let id: String           // filename without extension
    let url: URL
    let createdAt: Date
    let doc: CreatorPuzzleDoc
    var displayTitle: String {
        "Puzzle \(doc.difficulty ?? 0)/10 · \(doc.gradients.count) grads · \(doc.gridW)×\(doc.gridH)"
    }
}

enum GalleryStore {
    /// Root directory for saved puzzles. Created on first access.
    private static var rootDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("kroma", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save a live `Puzzle` to the gallery. Filename is timestamp-
    /// prefixed so chronological ordering = alphabetical ordering,
    /// which makes the fetch + sort path cheap.
    static func save(_ puzzle: Puzzle) throws -> URL {
        let json = try CreatorCodec.encodePuzzle(puzzle)
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "\(ts)-\(UUID().uuidString.prefix(8)).kroma"
        let url = rootDir.appendingPathComponent(filename)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// Save raw JSON payload (e.g. from an inbound .kroma file). Uses
    /// the same naming scheme; if the payload is malformed we throw.
    static func saveJSON(_ json: String) throws -> URL {
        guard let data = json.data(using: .utf8),
              let _ = try? CreatorCodec.decode(data) else {
            throw NSError(domain: "GalleryStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid puzzle JSON."])
        }
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "\(ts)-\(UUID().uuidString.prefix(8)).kroma"
        let url = rootDir.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// List every puzzle currently saved, newest first. Bad files
    /// (malformed JSON, stale versions) are silently skipped.
    static func all() -> [GalleryPuzzle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: rootDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [GalleryPuzzle] = []
        for url in entries where url.pathExtension == "kroma" {
            guard let data = try? Data(contentsOf: url),
                  let doc = try? CreatorCodec.decode(data) else { continue }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date()
            let id = url.deletingPathExtension().lastPathComponent
            out.append(GalleryPuzzle(id: id, url: url, createdAt: created, doc: doc))
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    /// Delete a saved puzzle. No-op if the file is already gone.
    static func delete(_ puzzle: GalleryPuzzle) throws {
        try? FileManager.default.removeItem(at: puzzle.url)
    }
}
