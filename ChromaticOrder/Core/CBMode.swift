//  Color-blindness modes. Drives both the generator's distance
//  calculations (so puzzles it builds are distinguishable by the
//  player's vision) and the UI label shown in the hamburger menu.
//
//  Coverage:
//    protanopia      — no L-cones, red/green collapse, red dark
//    deuteranopia    — no M-cones, red/green collapse, lightness preserved
//    tritanopia      — no S-cones, blue/yellow collapse (rare)
//    achromatopsia   — no color at all, luminance only
//
//  Anomaly (partial) variants are approximated by the full dichromatic
//  transform — the Machado matrices we use have a severity parameter;
//  using severity 1.0 is the conservative choice ("build for the
//  strongest case of the condition").

import Foundation

enum CBMode: String, Hashable, CaseIterable, Codable {
    case none
    case protanopia
    case deuteranopia
    case tritanopia
    case achromatopsia

    /// Long label for settings screens.
    var label: String {
        switch self {
        case .none:          return "Off"
        case .protanopia:    return "Protanopia"
        case .deuteranopia:  return "Deuteranopia"
        case .tritanopia:    return "Tritanopia"
        case .achromatopsia: return "Achromatopsia"
        }
    }

    /// Short label for space-constrained spots (menu buttons).
    var shortLabel: String {
        switch self {
        case .none:          return "Off"
        case .protanopia:    return "Protan"
        case .deuteranopia:  return "Deutan"
        case .tritanopia:    return "Tritan"
        case .achromatopsia: return "Achro"
        }
    }

    /// Cycle to the next mode — used by the menu toggle so the player
    /// can rotate through with repeated taps.
    func next() -> CBMode {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}
