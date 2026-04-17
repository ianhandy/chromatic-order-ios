//  Color-blindness simulation — Machado et al. (2009) 3x3 matrices
//  applied in linear-sRGB space. For each dichromatic mode, the matrix
//  projects the linear-light color onto the subspace that person
//  actually sees (protanopia: L-cone axis collapsed; deuteranopia:
//  M-cone axis collapsed; tritanopia: S-cone axis collapsed).
//  Achromatopsia is handled separately as Rec. 709 luminance-weighted
//  grayscale.
//
//  Matrices are severity 1.0 ("full" dichromacy). Anomaly variants
//  (protanomaly, etc.) sit on a gradient between severity 0 and 1;
//  we use the maximum so puzzles built for the CB player are
//  conservatively distinguishable — works for the partial case too.

import Foundation

enum CBTransform {
    /// Simulate the given OKLCh color as perceived under the given
    /// color-blindness mode. Round-trips: OKLCh → linear sRGB → apply
    /// matrix → linear sRGB' → OKLCh. For `.none`, pass-through.
    static func simulate(_ color: OKLCh, mode: CBMode) -> OKLCh {
        if mode == .none { return color }
        let rgb = OK.toLinearRGB(color)
        let out = applyRGB(rgb, mode: mode)
        return OK.fromLinearRGB(out)
    }

    /// Apply the CB transform directly in linear-sRGB space. Exposed so
    /// distance helpers can skip the round-trip back to OKLCh.
    static func applyRGB(
        _ rgb: (r: Double, g: Double, b: Double),
        mode: CBMode
    ) -> (r: Double, g: Double, b: Double) {
        switch mode {
        case .none:
            return rgb
        case .achromatopsia:
            // Rec. 709 luminance — weighted average with the human
            // eye's sensitivity to each primary.
            let y = 0.212656 * rgb.r + 0.715158 * rgb.g + 0.072186 * rgb.b
            return (y, y, y)
        case .protanopia, .deuteranopia, .tritanopia:
            let m = matrix(for: mode)
            return (
                m[0] * rgb.r + m[1] * rgb.g + m[2] * rgb.b,
                m[3] * rgb.r + m[4] * rgb.g + m[5] * rgb.b,
                m[6] * rgb.r + m[7] * rgb.g + m[8] * rgb.b
            )
        }
    }

    private static func matrix(for mode: CBMode) -> [Double] {
        switch mode {
        case .protanopia:
            return [
                 0.152286,  1.052583, -0.204868,
                 0.114503,  0.786281,  0.099216,
                -0.003882, -0.048116,  1.051998,
            ]
        case .deuteranopia:
            return [
                 0.367322,  0.860646, -0.227968,
                 0.280085,  0.672501,  0.047413,
                -0.011820,  0.042940,  0.968881,
            ]
        case .tritanopia:
            return [
                 1.255528, -0.076749, -0.178779,
                -0.078411,  0.930809,  0.147602,
                 0.004733,  0.691367,  0.303900,
            ]
        default:
            return [1, 0, 0, 0, 1, 0, 0, 0, 1]  // identity
        }
    }
}
