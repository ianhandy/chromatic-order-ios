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
    /// Player-chosen name, or nil if never set. Falls back to
    /// `autoTitle` in the UI when absent.
    var displayName: String { doc.name?.isEmpty == false ? doc.name! : autoTitle }
    var autoTitle: String {
        "Puzzle \(doc.difficulty ?? 0)/10 · \(doc.gradients.count) grads · \(doc.gridW)×\(doc.gridH)"
    }
    var subtitle: String {
        "Difficulty \(doc.difficulty ?? 0)/10 · \(doc.gradients.count) gradients"
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

    /// Save a live Puzzle with an optional player-chosen name baked
    /// into the JSON doc. Same timestamp-prefixed filename scheme as
    /// `save(_:)` so ordering stays stable.
    static func saveNamed(_ puzzle: Puzzle, name: String?) throws -> URL {
        let json = try CreatorCodec.encodePuzzle(puzzle)
        // Decode → set name → re-encode, so the stored file has the
        // title embedded. One extra round-trip per save — cheap.
        guard let data = json.data(using: .utf8),
              var doc = try? CreatorCodec.decode(data) else {
            throw NSError(domain: "GalleryStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not re-encode puzzle for save."])
        }
        doc.name = name
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "\(ts)-\(UUID().uuidString.prefix(8)).kroma"
        let url = rootDir.appendingPathComponent(filename)
        try write(doc, to: url)
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

    /// Rename a puzzle in place — rewrites the file with `doc.name`
    /// updated. The filename stays timestamped so ordering survives
    /// the rename; we're only touching the JSON body.
    static func rename(_ puzzle: GalleryPuzzle, to newName: String) throws {
        var doc = puzzle.doc
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.name = trimmed.isEmpty ? nil : trimmed
        try write(doc, to: puzzle.url)
    }

    /// Overwrite the saved puzzle's contents with a new doc (used by
    /// the gallery's "Edit" flow). Filename + creation date unchanged
    /// so the entry stays in place in the list.
    static func overwrite(_ puzzle: GalleryPuzzle, with doc: CreatorPuzzleDoc) throws {
        try write(doc, to: puzzle.url)
    }

    private static func write(_ doc: CreatorPuzzleDoc, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try enc.encode(doc)
        try data.write(to: url, options: .atomic)
    }
}
