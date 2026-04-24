//  Stores the set of gallery puzzle IDs the player has perfect-
//  solved. The Gallery list reads this to paint a small heart on
//  the top-left of each row that's been completed without burning
//  a heart or using Show Incorrect.
//
//  Storage: a single UserDefaults array under
//  `kromaGalleryPerfectSolves_v1`. Low volume — even an enthusiastic
//  curator caps out at a few dozen entries. Reset Progress leaves
//  these alone because achievement-like marks shouldn't vanish with
//  level/hearts reset.

import Foundation

enum GallerySolvedStore {
    private static let key = "kromaGalleryPerfectSolves_v1"

    static func hasPerfected(_ id: String) -> Bool {
        all().contains(id)
    }

    static func markPerfected(_ id: String) {
        var set = all()
        guard !set.contains(id) else { return }
        set.insert(id)
        persist(set)
    }

    static func all() -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [String] else {
            return []
        }
        return Set(arr)
    }

    private static func persist(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
