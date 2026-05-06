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

func labUnder(_ c: OKLCh, mode: CBMode) -> (L: Double, a: Double, b: Double) {
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

// ─── Trajectories in OKLab (Rule 4) ─────────────────────────────────
//
// A gradient's trajectory is the 3D line segment through all its
// stepped cell colors PLUS one extra step beyond each end. The
// hypothetical-next-cell endpoints let us see whether two gradients'
// lines would collide if extended. Computed in OKLab (Cartesian) so
// arithmetic is straightforward.

struct LabPoint: Hashable {
    let L: Double
    let a: Double
    let b: Double
}

struct GradientTrajectory {
    let gradientId: Int
    /// One step past `colors[0]` opposite to the direction of travel.
    let extrapolatedStart: LabPoint
    /// One step past `colors[last]` in the direction of travel.
    let extrapolatedEnd: LabPoint
    /// `extrapolatedStart` + every real cell color, in order,
    /// + `extrapolatedEnd`. N+2 points total, forming the full
    /// trajectory polyline including the hypothetical next cells.
    let stepPoints: [LabPoint]
}

/// Trajectory for a single gradient. For N == 1 (no step available),
/// both extrapolated endpoints collapse onto the single cell color.
func gradientTrajectory(_ g: PuzzleGradient, mode: CBMode = .none) -> GradientTrajectory {
    let labPoints = g.colors.map { labUnder($0, mode: mode) }
        .map { LabPoint(L: $0.L, a: $0.a, b: $0.b) }
    if labPoints.count == 1 {
        let p = labPoints[0]
        return GradientTrajectory(
            gradientId: g.id,
            extrapolatedStart: p, extrapolatedEnd: p,
            stepPoints: [p])
    }
    let first = labPoints.first!
    let last = labPoints.last!
    let steps = Double(labPoints.count - 1)
    let dL = (last.L - first.L) / steps
    let da = (last.a - first.a) / steps
    let db = (last.b - first.b) / steps
    let start = LabPoint(L: first.L - dL, a: first.a - da, b: first.b - db)
    let end   = LabPoint(L: last.L  + dL, a: last.a  + da, b: last.b  + db)
    var pts = [start]
    pts.append(contentsOf: labPoints)
    pts.append(end)
    return GradientTrajectory(
        gradientId: g.id,
        extrapolatedStart: start, extrapolatedEnd: end,
        stepPoints: pts)
}

/// Pairwise overlap between two gradient trajectories.
struct TrajectoryOverlap {
    let aId: Int
    let bId: Int
    /// Minimum ΔE between the two trajectory line segments (treated as
    /// bounded segments, not infinite lines). A value < ΔE 2 means the
    /// lines visibly intersect in color space — very difficult puzzle.
    let lineSegmentMinDistance: Double
    /// Minimum ΔE between any step-point on trajectory A and any step-
    /// point on trajectory B (both trajectories INCLUDE their
    /// extrapolated endpoints). A value < ΔE 2 means at least one cell
    /// (real or hypothetical-next) on one gradient is
    /// indistinguishable from a cell on the other.
    let nearestStepPointDistance: Double
}

private func lineSegDist(_ a1: LabPoint, _ a2: LabPoint,
                         _ b1: LabPoint, _ b2: LabPoint) -> Double {
    // Classic 3D segment-segment min distance (Lumelsky's algorithm).
    // Working in lab*100 so the returned value is in ΔE units directly.
    let u = (a2.L - a1.L, a2.a - a1.a, a2.b - a1.b)
    let v = (b2.L - b1.L, b2.a - b1.a, b2.b - b1.b)
    let w = (a1.L - b1.L, a1.a - b1.a, a1.b - b1.b)
    func dot(_ x: (Double, Double, Double), _ y: (Double, Double, Double)) -> Double {
        x.0 * y.0 + x.1 * y.1 + x.2 * y.2
    }
    let A = dot(u, u)
    let B = dot(u, v)
    let C = dot(v, v)
    let D = dot(u, w)
    let E = dot(v, w)
    let denom = A * C - B * B
    let eps = 1e-12
    var sN, sD, tN, tD: Double
    if denom < eps {
        sN = 0; sD = 1
        tN = E; tD = C
    } else {
        sN = B * E - C * D
        tN = A * E - B * D
        sD = denom; tD = denom
        if sN < 0 { sN = 0; tN = E; tD = C }
        else if sN > sD { sN = sD; tN = E + B; tD = C }
    }
    if tN < 0 {
        tN = 0
        if -D < 0 { sN = 0 }
        else if -D > A { sN = sD }
        else { sN = -D; sD = A }
    } else if tN > tD {
        tN = tD
        if (-D + B) < 0 { sN = 0 }
        else if (-D + B) > A { sN = sD }
        else { sN = -D + B; sD = A }
    }
    let sc = abs(sN) < eps ? 0 : sN / sD
    let tc = abs(tN) < eps ? 0 : tN / tD
    let dx = w.0 + sc * u.0 - tc * v.0
    let dy = w.1 + sc * u.1 - tc * v.1
    let dz = w.2 + sc * u.2 - tc * v.2
    return sqrt((dx * 100) * (dx * 100)
              + (dy * 100) * (dy * 100)
              + (dz * 100) * (dz * 100))
}

private func labDist(_ p: LabPoint, _ q: LabPoint) -> Double {
    let dL = (p.L - q.L) * 100
    let da = (p.a - q.a) * 100
    let db = (p.b - q.b) * 100
    return sqrt(dL * dL + da * da + db * db)
}

/// All pairwise trajectory overlaps (i < j). Two trajectories here are
/// EACH the extrapolated-endpoint line segment — we treat the full
/// trajectory as the straight segment from extrapolatedStart to
/// extrapolatedEnd, since the puzzle's stepped colors all lie on that
/// line by construction.
func trajectoryOverlaps(_ gradients: [PuzzleGradient],
                        mode: CBMode = .none) -> [TrajectoryOverlap] {
    let trajs = gradients.map { gradientTrajectory($0, mode: mode) }
    var out: [TrajectoryOverlap] = []
    for i in 0..<trajs.count {
        for j in (i + 1)..<trajs.count {
            let a = trajs[i], b = trajs[j]
            let lineDist = lineSegDist(a.extrapolatedStart, a.extrapolatedEnd,
                                       b.extrapolatedStart, b.extrapolatedEnd)
            var pointDist = Double.infinity
            for p in a.stepPoints {
                for q in b.stepPoints {
                    let d = labDist(p, q)
                    if d < pointDist { pointDist = d }
                }
            }
            out.append(TrajectoryOverlap(
                aId: a.gradientId, bId: b.gradientId,
                lineSegmentMinDistance: lineDist,
                nearestStepPointDistance: pointDist))
        }
    }
    return out
}

/// Summary stats across all gradient pairs: useful for quickly gating
/// a puzzle. Callers that want per-pair detail should use
/// `trajectoryOverlaps` directly.
struct TrajectoryOverlapSummary {
    /// Minimum line-segment distance across all gradient pairs. Lower
    /// == two gradients' trajectories are closer to intersecting in
    /// color space == visually harder puzzle.
    let minLineDistance: Double
    /// Minimum step-point distance across all gradient pairs.
    let minStepPointDistance: Double
    /// Count of gradient pairs whose line segments are within ΔE 2.
    let intersectingPairCount: Int
}

func trajectoryOverlapSummary(_ gradients: [PuzzleGradient],
                              mode: CBMode = .none) -> TrajectoryOverlapSummary {
    let overlaps = trajectoryOverlaps(gradients, mode: mode)
    if overlaps.isEmpty {
        return TrajectoryOverlapSummary(
            minLineDistance: .infinity,
            minStepPointDistance: .infinity,
            intersectingPairCount: 0)
    }
    let lineMin = overlaps.map { $0.lineSegmentMinDistance }.min() ?? .infinity
    let ptMin   = overlaps.map { $0.nearestStepPointDistance }.min() ?? .infinity
    let inter   = overlaps.filter { $0.lineSegmentMinDistance < 2 }.count
    return TrajectoryOverlapSummary(
        minLineDistance: lineMin,
        minStepPointDistance: ptMin,
        intersectingPairCount: inter)
}
