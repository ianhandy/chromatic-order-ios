//  Proximity metrics: how close gradients get in OKLab ΔE space.
//  Drives the generation gate + difficulty score. Swift port of the
//  relevant pieces of src/gradient.js.

import Foundation

// All proximity metrics take an optional CBMode. When non-.none, the
// distances are computed under the player's vision — so a puzzle that
// scores low pairProx for a normal-sighted player but high pairProx
// for a protanope will correctly flag as harder in Protan mode.
//
// For .none (the common path), behavior is identical to before.

private func labUnder(_ c: OKLCh, mode: CBMode) -> (L: Double, a: Double, b: Double) {
    if mode == .none { return OK.toLab(c) }
    return OK.linearRGBToLab(CBTransform.applyRGB(OK.toLinearRGB(c), mode: mode))
}

// ΔE from point `p` to the INFINITE line through endpoints of `line`.
func distToInfiniteLine(_ p: OKLCh, _ line: [OKLCh], mode: CBMode = .none) -> Double {
    guard line.count >= 2 else { return .infinity }
    let a = labUnder(line.first!, mode: mode)
    let b = labUnder(line.last!, mode: mode)
    let pp = labUnder(p, mode: mode)
    let dx = b.L - a.L, dy = b.a - a.a, dz = b.b - a.b
    let denom = dx * dx + dy * dy + dz * dz
    if denom < 1e-12 { return .infinity }
    let t = ((pp.L - a.L) * dx + (pp.a - a.a) * dy + (pp.b - a.b) * dz) / denom
    let px = a.L + t * dx, py = a.a + t * dy, pz = a.b + t * dz
    let dL = (pp.L - px) * 100, da = (pp.a - py) * 100, db = (pp.b - pz) * 100
    return (dL * dL + da * da + db * db).squareRoot()
}

// ΔE from `p` to nearest segment of the polyline through `line`.
func distToPolyline(_ p: OKLCh, _ line: [OKLCh], mode: CBMode = .none) -> Double {
    var best = Double.infinity
    let pp = labUnder(p, mode: mode)
    for i in 0..<(line.count - 1) {
        let a = labUnder(line[i], mode: mode)
        let b = labUnder(line[i + 1], mode: mode)
        let dx = b.L - a.L, dy = b.a - a.a, dz = b.b - a.b
        let denom = dx * dx + dy * dy + dz * dz
        if denom < 1e-12 { continue }
        let tRaw = ((pp.L - a.L) * dx + (pp.a - a.a) * dy + (pp.b - a.b) * dz) / denom
        let t = max(0, min(1, tRaw))
        let px = a.L + t * dx, py = a.a + t * dy, pz = a.b + t * dz
        let dL = (pp.L - px) * 100, da = (pp.a - py) * 100, db = (pp.b - pz) * 100
        let d = (dL * dL + da * da + db * db).squareRoot()
        if d < best { best = d }
    }
    return best
}

func minInterGradientLineDist(_ groups: [[OKLCh]], mode: CBMode = .none) -> Double {
    var minD = Double.infinity
    for i in 0..<groups.count {
        for j in 0..<groups.count where i != j {
            for p in groups[i] {
                if groups[j].contains(where: { OK.equal(p, $0, mode: mode) }) { continue }
                let d = distToPolyline(p, groups[j], mode: mode)
                if d < minD { minD = d }
            }
        }
    }
    return minD
}

// Cross-gradient close-cell penalty. Every pair of cells on different
// gradients within NEAR ΔE contributes a quadratic penalty that spikes
// as distance shrinks. Intersections (equal-ΔE) skipped.
func cellPairProximityScore(_ gradients: [PuzzleGradient], mode: CBMode = .none) -> Double {
    let NEAR = 12.0
    var score = 0.0
    for i in 0..<gradients.count {
        for j in (i + 1)..<gradients.count {
            for a in gradients[i].colors {
                for b in gradients[j].colors {
                    if OK.equal(a, b, mode: mode) { continue }
                    let d = OK.dist(a, b, mode: mode)
                    if d < NEAR {
                        let t = (NEAR - d) / NEAR
                        score += t * t
                    }
                }
            }
        }
    }
    return score
}

// "Cell could extend that other gradient" penalty.
func extrapolationProximityScore(_ gradients: [PuzzleGradient], mode: CBMode = .none) -> Double {
    let NEAR = 8.0
    var score = 0.0
    for i in 0..<gradients.count {
        for j in 0..<gradients.count where i != j {
            for p in gradients[i].colors {
                if gradients[j].colors.contains(where: { OK.equal(p, $0, mode: mode) }) { continue }
                let d = distToInfiniteLine(p, gradients[j].colors, mode: mode)
                if d < NEAR {
                    let t = (NEAR - d) / NEAR
                    score += t * t
                }
            }
        }
    }
    return score
}
