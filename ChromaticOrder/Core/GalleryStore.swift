//  On-disk store of player-created + received puzzles. Lives under
//  ~/Documents/kroma/ — the app's sandboxed Documents directory, so
//  files survive offloads and iCloud backups where enabled. Each
//  puzzle is a single .kroma JSON file with a timestamp-prefixed
//  filename; metadata (grid size, difficulty, gradient count) is
//  parsed from the JSON on read, no sidecar.
//
//  Collections live under ~/Documents/kroma/collections/<uuid>/, each
//  with a _meta.json storing the display name. A UUID directory lets
//  rename work without moving files.

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

struct GalleryCollection: Identifiable, Hashable {
    let id: String           // UUID directory name
    let url: URL             // directory URL
    var name: String
    var createdAt: Date
    var puzzleCount: Int

    static func == (lhs: GalleryCollection, rhs: GalleryCollection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct CollectionMeta: Codable {
    var name: String
    var createdAt: TimeInterval
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

    private static var collectionsDir: URL {
        let dir = rootDir.appendingPathComponent("collections", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // ─── Save ──────────────────────────────────────────────────────

    /// Save a live `Puzzle` to the gallery. Filename is timestamp-
    /// prefixed so chronological ordering = alphabetical ordering,
    /// which makes the fetch + sort path cheap.
    static func save(_ puzzle: Puzzle, in collection: GalleryCollection? = nil) throws -> URL {
        let json = try CreatorCodec.encodePuzzle(puzzle)
        let url = newPuzzleURL(in: collection)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    /// Save a live Puzzle with an optional player-chosen name baked
    /// into the JSON doc. Same timestamp-prefixed filename scheme as
    /// `save(_:)` so ordering stays stable.
    static func saveNamed(_ puzzle: Puzzle, name: String?, in collection: GalleryCollection? = nil) throws -> URL {
        let json = try CreatorCodec.encodePuzzle(puzzle)
        guard let data = json.data(using: .utf8),
              var doc = try? CreatorCodec.decode(data) else {
            throw NSError(domain: "GalleryStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not re-encode puzzle for save."])
        }
        doc.name = name
        let url = newPuzzleURL(in: collection)
        try write(doc, to: url)
        return url
    }

    /// Save raw JSON payload (e.g. from an inbound .kroma file). Uses
    /// the same naming scheme; if the payload is malformed we throw.
    static func saveJSON(_ json: String, in collection: GalleryCollection? = nil) throws -> URL {
        guard let data = json.data(using: .utf8),
              let _ = try? CreatorCodec.decode(data) else {
            throw NSError(domain: "GalleryStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid puzzle JSON."])
        }
        let url = newPuzzleURL(in: collection)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func newPuzzleURL(in collection: GalleryCollection?) -> URL {
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "\(ts)-\(UUID().uuidString.prefix(8)).kroma"
        let parent = collection?.url ?? rootDir
        return parent.appendingPathComponent(filename)
    }

    // ─── Query ─────────────────────────────────────────────────────

    /// List every loose puzzle at the root (not inside a collection),
    /// newest first. Bad files are silently skipped.
    static func all() -> [GalleryPuzzle] {
        puzzles(in: rootDir)
    }

    /// List puzzles inside a specific collection, newest first.
    static func puzzles(in collection: GalleryCollection) -> [GalleryPuzzle] {
        puzzles(in: collection.url)
    }

    private static func puzzles(in dir: URL) -> [GalleryPuzzle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
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

    // ─── Puzzle mutations ──────────────────────────────────────────

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

    /// Move a puzzle into `collection`, or back to the root if `nil`.
    /// Filename is preserved (timestamped), so ordering stays stable.
    /// Returns the new URL so callers can update any held reference.
    @discardableResult
    static func movePuzzle(_ puzzle: GalleryPuzzle, to collection: GalleryCollection?) throws -> URL {
        let parent = collection?.url ?? rootDir
        let destination = parent.appendingPathComponent(puzzle.url.lastPathComponent)
        if destination == puzzle.url { return puzzle.url }
        try FileManager.default.moveItem(at: puzzle.url, to: destination)
        return destination
    }

    // ─── Collections ───────────────────────────────────────────────

    /// All collections, alphabetical by name. Directories that are
    /// missing _meta.json are tolerated by falling back to the
    /// directory id as the display name.
    static func collections() -> [GalleryCollection] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: collectionsDir,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [GalleryCollection] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let id = url.lastPathComponent
            let metaURL = url.appendingPathComponent("_meta.json")
            let meta = (try? Data(contentsOf: metaURL))
                .flatMap { try? JSONDecoder().decode(CollectionMeta.self, from: $0) }
            let name = meta?.name ?? id
            let created: Date = {
                if let t = meta?.createdAt { return Date(timeIntervalSince1970: t) }
                return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            }()
            let count = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "kroma" }.count ?? 0
            out.append(GalleryCollection(id: id, url: url, name: name,
                                         createdAt: created, puzzleCount: count))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Create a new collection with `name`. The directory is a UUID;
    /// the display name lives in _meta.json alongside the creation ts.
    @discardableResult
    static func createCollection(name: String) throws -> GalleryCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled" : trimmed
        let id = UUID().uuidString
        let url = collectionsDir.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let meta = CollectionMeta(name: finalName, createdAt: Date().timeIntervalSince1970)
        try writeMeta(meta, in: url)
        return GalleryCollection(id: id, url: url, name: finalName,
                                 createdAt: Date(timeIntervalSince1970: meta.createdAt),
                                 puzzleCount: 0)
    }

    /// Rename a collection — rewrites _meta.json; directory name is
    /// the stable UUID and stays put.
    static func renameCollection(_ collection: GalleryCollection, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled" : trimmed
        let meta = CollectionMeta(name: finalName,
                                  createdAt: collection.createdAt.timeIntervalSince1970)
        try writeMeta(meta, in: collection.url)
    }

    /// Delete a collection and everything inside it. No-op if already
    /// gone.
    static func deleteCollection(_ collection: GalleryCollection) throws {
        try? FileManager.default.removeItem(at: collection.url)
    }

    // ─── Internal helpers ──────────────────────────────────────────

    private static func write(_ doc: CreatorPuzzleDoc, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try enc.encode(doc)
        try data.write(to: url, options: .atomic)
    }

    private static func writeMeta(_ meta: CollectionMeta, in dir: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try enc.encode(meta)
        try data.write(to: dir.appendingPathComponent("_meta.json"), options: .atomic)
    }
}
