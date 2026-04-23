//  Icon / theme picker shown in the Options sheet. The four variants
//  are visual palette themes previewed as 3×3 palette grids inside
//  the picker row and also swap the home-screen icon via
//  UIApplication.setAlternateIconName. The `iconName` computed
//  property maps each variant to the asset key registered in
//  project.yml's CFBundleAlternateIcons.

import SwiftUI
import UIKit

enum AppIconVariant: String, CaseIterable, Identifiable {
    case pastelPinks
    case neonGreens
    case earthyTones
    case rainbow

    /// Asset-catalog key registered in project.yml's
    /// CFBundleAlternateIcons. Matches the PNG file stems in
    /// ChromaticOrder/AlternateIcons/ (e.g. AppIconPastelPinks@2x.png).
    var iconName: String {
        switch self {
        case .pastelPinks: return "AppIconPastelPinks"
        case .neonGreens:  return "AppIconNeonGreens"
        case .earthyTones: return "AppIconEarthyTones"
        case .rainbow:     return "AppIconRainbow"
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pastelPinks: return "pastel pinks"
        case .neonGreens:  return "neon greens"
        case .earthyTones: return "earthy tones"
        case .rainbow:     return "rainbow"
        }
    }

    /// Row-major 3×3 palette grid. Every row AND every column is a
    /// real gradient — each theme picks four corner colors
    /// (top-left, top-right, bottom-left, bottom-right) and the
    /// interior cells are bilinear OKLab interpolations. That
    /// guarantees a valid Chromatic-Order-style puzzle layout
    /// (rows step smoothly, columns step smoothly, center is the
    /// intersection of both).
    var paletteGrid: [OKLCh] {
        let c = corners
        return Self.bilinearGrid(
            topLeft: c.tl, topRight: c.tr,
            bottomLeft: c.bl, bottomRight: c.br
        )
    }

    /// Four corner colors that define the theme's gradient. Interior
    /// cells are interpolated — so picking expressive corners is all
    /// we have to do per theme.
    private var corners: (tl: OKLCh, tr: OKLCh, bl: OKLCh, br: OKLCh) {
        switch self {
        case .pastelPinks:
            // Warm blush across the top, desaturated rose at the
            // bottom. Every row warms left→right; every column
            // deepens top→bottom.
            return (
                tl: OKLCh(L: 0.93, c: 0.04, h: 355),
                tr: OKLCh(L: 0.88, c: 0.07, h: 30),
                bl: OKLCh(L: 0.72, c: 0.11, h: 335),
                br: OKLCh(L: 0.68, c: 0.13, h: 10)
            )
        case .neonGreens:
            // Electric lime top-left → mint top-right → deep
            // emerald bottom-left → teal bottom-right.
            return (
                tl: OKLCh(L: 0.88, c: 0.22, h: 130),
                tr: OKLCh(L: 0.86, c: 0.18, h: 165),
                bl: OKLCh(L: 0.60, c: 0.25, h: 140),
                br: OKLCh(L: 0.56, c: 0.22, h: 175)
            )
        case .earthyTones:
            // Sand → moss across the top, terra-cotta → dark umber
            // across the bottom. Everything sits in the L 0.4–0.7
            // band so the theme reads as natural, grounded.
            return (
                tl: OKLCh(L: 0.70, c: 0.07, h: 80),
                tr: OKLCh(L: 0.60, c: 0.09, h: 110),
                bl: OKLCh(L: 0.46, c: 0.12, h: 35),
                br: OKLCh(L: 0.40, c: 0.09, h: 55)
            )
        case .rainbow:
            // A proper quadrant of the wheel — red → yellow across
            // the top, violet → cyan across the bottom. Every row
            // and column stays a clean hue ramp.
            return (
                tl: OKLCh(L: 0.65, c: 0.20, h: 20),
                tr: OKLCh(L: 0.82, c: 0.18, h: 95),
                bl: OKLCh(L: 0.55, c: 0.20, h: 305),
                br: OKLCh(L: 0.70, c: 0.18, h: 195)
            )
        }
    }

    /// Bilinear OKLab interpolation — each output cell is
    /// `lerp(lerp(tl, tr, tC), lerp(bl, br, tC), tR)`. Returns the
    /// 9 colors in row-major order for the picker preview grid.
    private static func bilinearGrid(topLeft tl: OKLCh,
                                      topRight tr: OKLCh,
                                      bottomLeft bl: OKLCh,
                                      bottomRight br: OKLCh) -> [OKLCh] {
        var out: [OKLCh] = []
        for r in 0..<3 {
            let tR = Double(r) / 2.0
            for c in 0..<3 {
                let tC = Double(c) / 2.0
                let top = lerpLab(tl, tr, tC)
                let bottom = lerpLab(bl, br, tC)
                out.append(lerpLab(top, bottom, tR))
            }
        }
        return out
    }

    /// Single-t OKLab lerp — interpolate in perceptual space and
    /// recover the OKLCh (L, c, h) triple on the far side. Handles
    /// hue wrap naturally via atan2.
    private static func lerpLab(_ a: OKLCh, _ b: OKLCh, _ t: Double) -> OKLCh {
        let la = OK.toLab(a), lb = OK.toLab(b)
        let L = la.L + (lb.L - la.L) * t
        let A = la.a + (lb.a - la.a) * t
        let B = la.b + (lb.b - la.b) * t
        let c = (A * A + B * B).squareRoot()
        var h = atan2(B, A) * 180 / .pi
        if h < 0 { h += 360 }
        return OKLCh(L: L, c: c, h: h)
    }
}

@MainActor
enum AppIconPicker {
    private static let prefsKey = "selectedAppIconVariant_v2"

    /// Current variant — persisted so the picker check-mark survives
    /// across launches. Defaults to pastelPinks.
    static var current: AppIconVariant {
        let raw = UserDefaults.standard.string(forKey: prefsKey) ?? ""
        return AppIconVariant(rawValue: raw) ?? .pastelPinks
    }

    /// Apply the selection: persist the choice and swap the
    /// home-screen icon. iOS only cares about the asset name (no
    /// extension, no @2x suffix) and picks the right resolution
    /// automatically. The no-op callback is required — passing nil
    /// logs a UIKit warning on some iOS versions.
    static func apply(_ variant: AppIconVariant) {
        UserDefaults.standard.set(variant.rawValue, forKey: prefsKey)
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        app.setAlternateIconName(variant.iconName) { _ in }
    }
}
