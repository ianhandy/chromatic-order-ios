//  On-disk store of player-favorited generator/custom puzzles. Lives
//  under ~/Documents/favorites/ — separate from the user-created
//  `kroma/` directory so the gallery can keep the two lists apart.
//  Each favorite is a single .kroma JSON file with the same schema
//  as the gallery; the GalleryPuzzle type serves both stores.

import Foundation

enum FavoritesStore {
    private static var rootDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("favorites", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
        }
        return dir
    }

    /// Save a live `Puzzle` as a favorite. Same timestamp-prefixed
    /// filename scheme as the gallery so chronological ordering =
    /// alphabetical ordering.
    static func save(_ puzzle: Puzzle) throws -> URL {
        let json = try CreatorCodec.encodePuzzle(puzzle)
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "\(ts)-\(UUID().uuidString.prefix(8)).kroma"
        let url = rootDir.appendingPathComponent(filename)
        try json.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

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

    static func delete(_ puzzle: GalleryPuzzle) throws {
        try? FileManager.default.removeItem(at: puzzle.url)
    }

    static func deleteURL(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
