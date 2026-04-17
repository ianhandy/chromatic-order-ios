//  OKLCh color primitives — Swift port of src/oklch.js.
//
//  OKLCh (Björn Ottosson, 2020) is a perceptually uniform cylindrical
//  color space. Euclidean distance in the companion OKLab (L, a, b)
//  coordinates closely matches human-perceived color difference, so
//  "these two cells look similar" means what it says.
//
//  Coordinates used throughout: { L, c, h }
//    L: lightness       [0, 1]
//    c: chroma          [0, ~0.4]
//    h: hue angle (°)   [0, 360)
//
//  ΔE magnitudes (roughly CIELAB-calibrated):
//    ≈ 2    just-noticeable difference (JND)
//    ≈ 5    small but visible
//    ≈ 10   clearly distinct
//    ≈ 25+  obviously different

import SwiftUI

struct OKLCh: Hashable {
    var L: Double
    var c: Double
    var h: Double
}

enum OK {
    // Usable perceptual band — cells outside this go gray (c too low) or
    // desaturate / clip at the luminance extremes.
    static let lMin: Double = 0.24
    static let lMax: Double = 0.86
    static let cMin: Double = 0.03
    static let cMax: Double = 0.33

    static func normH(_ h: Double) -> Double {
        let x = h.truncatingRemainder(dividingBy: 360)
        return x < 0 ? x + 360 : x
    }

    // OKLCh → OKLab. a, b are the Cartesian chroma components; the
    // Euclidean distance in (L, a, b) is the perceptual ΔE.
    static func toLab(_ color: OKLCh) -> (L: Double, a: Double, b: Double) {
        let hr = color.h * .pi / 180
        return (color.L, color.c * cos(hr), color.c * sin(hr))
    }

    // Perceptual distance, scaled ×100 so magnitudes match CIELAB ΔE
    // conventions (JND ≈ 2, distinct ≈ 10).
    static func dist(_ a: OKLCh, _ b: OKLCh) -> Double {
        let p = toLab(a), q = toLab(b)
        let dL = (p.L - q.L) * 100
        let da = (p.a - q.a) * 100
        let db = (p.b - q.b) * 100
        return (dL * dL + da * da + db * db).squareRoot()
    }

    // Cells with ΔE < 2 cannot be visually distinguished — treat them as
    // the same color for duplicate checks and fixed-point matching.
    static func equal(_ a: OKLCh, _ b: OKLCh) -> Bool { dist(a, b) < 2 }

    // OKLCh → linear sRGB (gamut check only; rendering uses SwiftUI's
    // native Color(.displayP3...) via toColor below).
    private static func toLinearRGB(_ color: OKLCh) -> (r: Double, g: Double, b: Double) {
        let hr = color.h * .pi / 180
        let a = color.c * cos(hr)
        let b = color.c * sin(hr)
        let l_ = color.L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = color.L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = color.L - 0.0894841775 * a - 1.2914855480 * b
        let ll = l_ * l_ * l_
        let mm = m_ * m_ * m_
        let ss = s_ * s_ * s_
        return (
            4.0767416621 * ll - 3.3077115913 * mm + 0.2309699292 * ss,
            -1.2684380046 * ll + 2.6097574011 * mm - 0.3413193965 * ss,
            -0.0041960863 * ll - 0.7034186147 * mm + 1.7076147010 * ss
        )
    }

    static func inGamut(_ color: OKLCh) -> Bool {
        let rgb = toLinearRGB(color)
        let eps = 0.005
        return rgb.r >= -eps && rgb.r <= 1 + eps
            && rgb.g >= -eps && rgb.g <= 1 + eps
            && rgb.b >= -eps && rgb.b <= 1 + eps
    }

    // "Usable" = inside the perceptual band. sRGB gamut check is skipped
    // (too aggressive — rejects ~50% of mid-chroma colors). SwiftUI will
    // clamp out-of-gamut colors to the display on render.
    static func inUsableBand(_ color: OKLCh) -> Bool {
        color.L >= lMin && color.L <= lMax
            && color.c >= cMin && color.c <= cMax
    }

    // Linear-sRGB → gamma-corrected sRGB, used by toColor below.
    private static func encode(_ v: Double) -> Double {
        let x = max(0.0, min(1.0, v))
        return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1.0 / 2.4) - 0.055
    }

    // SwiftUI Color. Gamut-clipped to sRGB on the way out because UIKit
    // has no native OKLCh. The clip is rarely visible because the puzzle
    // generator stays inside a hand-picked usable band anyway.
    static func toColor(_ c: OKLCh, opacity: Double = 1) -> Color {
        let rgb = toLinearRGB(c)
        return Color(.sRGB,
                     red: encode(rgb.r),
                     green: encode(rgb.g),
                     blue: encode(rgb.b),
                     opacity: opacity)
    }

    // Opposite hue, inverted lightness — "complement" of a color. Used
    // for readable text over a colored cell.
    static func opposite(_ c: OKLCh) -> OKLCh {
        OKLCh(L: 1 - c.L, c: c.c, h: normH(c.h + 180))
    }

    // Soft pastel tint in the same hue. Fixed near-white L + low chroma
    // keeps every tint readable regardless of source color.
    static func tint(_ c: OKLCh) -> OKLCh {
        OKLCh(L: 0.95, c: 0.035, h: c.h)
    }
}
