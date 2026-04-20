//  Mirrors a small allowlist of UserDefaults keys into iCloud's
//  NSUbiquitousKeyValueStore so zen progress + stats follow a player
//  across their devices. Writes are idempotent — the local UserDefaults
//  value stays authoritative for the running session; iCloud is the
//  shared source of truth between launches. Conflict resolution is
//  "last write wins," delegated to iCloud's own timestamping.

import Foundation

enum CloudSync {
    private static let keys = [
        "chromaticOrderProgress",  // zen level + zenMaxLevel
        "kromaStats_v1",           // aggregate stats
    ]

    /// Call once at app launch. Pulls the iCloud copy of each tracked
    /// key into UserDefaults if the remote value differs, then wires a
    /// listener so external changes land while the app is running.
    static func start() {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        merge(from: store)
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { _ in
            merge(from: store)
        }
    }

    /// Push a single tracked key's current UserDefaults value up to
    /// iCloud. Call from the local save path. No-op for untracked keys.
    static func push(_ key: String) {
        guard keys.contains(key) else { return }
        let local = UserDefaults.standard.data(forKey: key)
        NSUbiquitousKeyValueStore.default.set(local, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Adopt iCloud values into UserDefaults when the cloud has newer
    /// data (or the local copy is missing). Posts a notification so the
    /// running GameState can reload progress if it just changed.
    private static func merge(from store: NSUbiquitousKeyValueStore) {
        var anyChanged = false
        for key in keys {
            guard let remote = store.data(forKey: key) else { continue }
            let local = UserDefaults.standard.data(forKey: key)
            if local != remote {
                UserDefaults.standard.set(remote, forKey: key)
                anyChanged = true
            }
        }
        if anyChanged {
            NotificationCenter.default.post(
                name: .kromaCloudSyncDidMerge, object: nil
            )
        }
    }
}

extension Notification.Name {
    static let kromaCloudSyncDidMerge = Notification.Name("kromaCloudSyncDidMerge")
}
