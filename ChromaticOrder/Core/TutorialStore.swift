//  One-time tutorial + first-launch flag storage. Each flag lives
//  under its own UserDefaults key so we can version them
//  independently — bump the suffix if a tutorial's copy changes
//  enough to warrant re-showing.

import Foundation

enum TutorialFlag: String, CaseIterable {
    /// Very first cold launch. When unset, the app auto-drops the
    /// player into challenge mode with the challenge tutorial.
    case firstLaunch
    /// First-time zen-mode entry.
    case zenIntro
    /// First-time daily-puzzle entry.
    case dailyIntro

    /// Fixed RNG seed for the puzzle shown while this tutorial is
    /// pending. The tooltip copy + layout was designed around the
    /// specific puzzle each seed produces — gradient count, cell
    /// positions, bank swatch order. Randomizing meant the tooltip
    /// sometimes landed on top of the only colors the player was
    /// meant to focus on. Bump the seed's low bits if the copy or
    /// the tooltip's target area changes enough to warrant a
    /// different reference puzzle.
    var puzzleSeed: UInt64 {
        switch self {
        case .firstLaunch: return 0xC01D_BEEF_C0DE_0001
        case .zenIntro:    return 0xC01D_BEEF_C0DE_0002
        case .dailyIntro:  return 0xC01D_BEEF_C0DE_0003
        }
    }
}

enum TutorialStore {
    private static func key(_ flag: TutorialFlag) -> String {
        "tutorial_\(flag.rawValue)_v1"
    }

    static func hasSeen(_ flag: TutorialFlag) -> Bool {
        UserDefaults.standard.bool(forKey: key(flag))
    }

    static func markSeen(_ flag: TutorialFlag) {
        UserDefaults.standard.set(true, forKey: key(flag))
    }

    static func resetAll() {
        for f in TutorialFlag.allCases {
            UserDefaults.standard.removeObject(forKey: key(f))
        }
    }
}
