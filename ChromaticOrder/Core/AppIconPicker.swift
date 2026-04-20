//  Alternate app icon selection. iOS sets the home-screen icon at the
//  system level via setAlternateIconName(_:) — nil restores the
//  default. Names must match the CFBundleAlternateIcons keys declared
//  in Info.plist (project.yml) or the call no-ops.

import SwiftUI
import UIKit

enum AppIconVariant: String, CaseIterable, Identifiable {
    case `default` = "default"
    case easy = "AppIconEasy"
    case medium = "AppIconMedium"
    case hard = "AppIconHard"
    case expert = "AppIconExpert"

    var id: String { rawValue }

    /// Display label for the picker row.
    var displayName: String {
        switch self {
        case .default: return "default"
        case .easy: return "easy green"
        case .medium: return "medium gold"
        case .hard: return "hard orange"
        case .expert: return "expert red"
        }
    }

    /// The name passed to setAlternateIconName — nil resets to default.
    var iconName: String? {
        self == .default ? nil : rawValue
    }

    /// Representative tone for the preview swatch in the picker.
    var swatch: OKLCh {
        switch self {
        case .default: return OKLCh(L: 0.65, c: 0.0, h: 0)
        case .easy: return OKLCh(L: 0.62, c: 0.14, h: 150)
        case .medium: return OKLCh(L: 0.72, c: 0.12, h: 85)
        case .hard: return OKLCh(L: 0.60, c: 0.17, h: 55)
        case .expert: return OKLCh(L: 0.55, c: 0.19, h: 25)
        }
    }
}

@MainActor
enum AppIconPicker {
    /// Current icon variant, derived from UIApplication's record of the
    /// last alternate-icon set. Returns `.default` when iOS reports nil.
    static var current: AppIconVariant {
        guard UIApplication.shared.supportsAlternateIcons,
              let name = UIApplication.shared.alternateIconName,
              let variant = AppIconVariant(rawValue: name) else {
            return .default
        }
        return variant
    }

    /// Apply a variant. iOS pops a system "icon changed" alert — no
    /// way to suppress it without private API; we accept the UX.
    static func apply(_ variant: AppIconVariant) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(variant.iconName) { _ in }
    }
}
