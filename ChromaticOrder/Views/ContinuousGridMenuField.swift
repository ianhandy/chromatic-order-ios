//  Alt main-menu backdrop — a continuous dense grid of OKLCh swatches
//  whose hues drift over time. Dynamic elements on top:
//
//  • Flares — single-cell-wide pulses that travel along a row or
//    column. One fires every time an audio note plays (the field
//    listens on NotificationCenter for `.kromaNotePlayed`), plus a
//    steady ambient cadence so the menu never goes silent-looking.
//    Long life + wide radius = generous fading streaks.
//  • Ripples — same pulse, radiating outward in a circle from
//    wherever the player touches. Pushed in via `ripples` binding.
//  • "Current" wave — every cell grows and shrinks on a traveling
//    sine wave so the field always looks like it's breathing even
//    when no flares or ripples are in flight.
//
//  Envelope for flares/ripples: high attack (~80 ms) → long
//  exponential decay. Cells within the pulse see a lift in alpha and
//  L; the scale wave is independent and persistent.

import SwiftUI

struct GridFlare {
    enum Kind { case row, col }
    let kind: Kind
    /// Normalized axis in [0, 1); resolved to an actual row/col
    /// index at draw time by multiplying by the current grid
    /// dimension.
    let axisNorm: Double
    var direction: Double   // +1 = toward higher indices, -1 = lower
    var speed: Double       // cells per second
    var spawnEpoch: Double  // TimeInterval from reference date
    let lifeSec: Double
    /// Absolute end of the flare's lifetime. Kept independent of redraws
    /// and touch-state changes so interaction never clears a live line.
    let expiresEpoch: Double
    /// A flare gets one collision accent. The two original lines continue
    /// untouched; this guard only prevents the same pair from spawning a
    /// new impact ring every resolver tick.
    var hasCollided = false
    /// Per-flare hue shift (degrees). Applied to cells this flare
    /// lights up, scaled by the flare's contribution — gives each
    /// flare its own color tint so distinct flares paint distinct
    /// streaks. Picked uniformly in [-45°, +45°] at spawn. Mutable
    /// so collisions can swap tints alongside direction/speed.
    var hueOffset: Double
}

struct GridRipple: Identifiable {
    let id = UUID()
    let origin: CGPoint     // view-local point coords
    let speed: Double       // cells/sec — outward radius velocity
    let spawnEpoch: Double
    let lifeSec: Double
    /// Multiplier on this ripple's visual impact (both cell boost
    /// and physical displacement). Default 1.0 for finger ripples;
    /// flare wakes and collision impacts use higher values so their
    /// rings read without having to climb above the flares they
    /// live alongside.
    var strength: Double = 1.0

    init(origin: CGPoint,
         speed: Double,
         spawnEpoch: Double,
         lifeSec: Double,
         strength: Double = 1.0) {
        self.origin = origin
        self.speed = speed
        self.spawnEpoch = spawnEpoch
        self.lifeSec = lifeSec
        self.strength = strength
    }
}

extension Notification.Name {
    /// Posted by GlassyAudio each time a playable note/chord goes
    /// out. `userInfo["semitone"]` carries a representative MIDI
    /// semitone. The continuous-grid menu backdrop listens and
    /// spawns a flare keyed to the pitch.
    static let kromaNotePlayed = Notification.Name("kromaNotePlayed")
}

struct ContinuousGridMenuField: View {
    let hueSeed: Double
    let fps: Int
    /// Ripples owned by the parent (menu view) so tap/drag gestures
    /// up there can append new ones. Pruned from within this view
    /// once they expire.
    @Binding var ripples: [GridRipple]

    /// MenuView owns both visual collections. Keeping them at the same
    /// identity level means a touch update cannot recreate this renderer
    /// and accidentally discard the already-traveling gradients.
    @Binding var flares: [GridFlare]
    @State private var lastAmbientFlareSpawn: Double = 0
    @State private var lastAudioFlareSpawn: Double = 0
    /// Grid dimensions observed during the last Canvas draw. Used by
    /// the collision resolver (which runs off the render loop) so it
    /// can compute each flare's current head cell in the same
    /// coordinate space the draw loop uses.
    @State private var cachedCols: Int = 0
    @State private var cachedRows: Int = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / Double(max(15, fps)))) { timeline in
                Canvas { ctx, size in
                    draw(ctx: ctx, size: size, time: timeline.date)
                }
            }
            .onAppear { cacheGridSize(geometry.size) }
            .onChange(of: geometry.size) { _, size in cacheGridSize(size) }
        }
        .task {
            // Flare head collisions — tight cadence so fast flares
            // don't skip past each other between checks. A collision
            // adds a restrained fluid accent while both lines continue
            // along their existing paths.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 66_000_000)   // ~15 Hz
                let now = Date().timeIntervalSinceReferenceDate
                resolveFlareCollisions(now: now,
                                        cols: cachedCols,
                                        rows: cachedRows)
            }
        }
        .task {
            // Flare + ripple maintenance. Runs off the render loop so
            // the Canvas draw closure stays purely read-only.
            lastAmbientFlareSpawn = Date().timeIntervalSinceReferenceDate
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 300 ms
                let now = Date().timeIntervalSinceReferenceDate
                flares.removeAll { now > $0.expiresEpoch }
                ripples.removeAll { now - $0.spawnEpoch > $0.lifeSec }
                if flares.count > 12 { flares.removeFirst(flares.count - 12) }
                if ripples.count > 16 { ripples.removeFirst(ripples.count - 16) }
                // Ambient flare every 2–3.5 s so the field has
                // movement even when no audio is triggering flares.
                let interval = Double.random(in: 2.0...3.5)
                if now - lastAmbientFlareSpawn > interval {
                    flares.append(randomFlare(now: now, semitone: nil))
                    lastAmbientFlareSpawn = now
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kromaNotePlayed)) { note in
            let semi = (note.userInfo?["semitone"] as? Int)
            let now = Date().timeIntervalSinceReferenceDate
            // Chords can post several notes in the same instant. One
            // visual accent per quarter-second keeps the music legible
            // without multiplying full-grid work for every voice.
            guard now - lastAudioFlareSpawn >= 0.40 else { return }
            lastAudioFlareSpawn = now
            flares.append(randomFlare(now: now, semitone: semi))
        }
        .allowsHitTesting(false)
    }

    // ─── Drawing ────────────────────────────────────────────────────

    private static let cellPx: CGFloat = 28
    private static let gap: CGFloat = 3
    private static let pitch: CGFloat = cellPx + gap
    /// Falloff radius (in cells) for flare streaks. Wider = thicker,
    /// softer-edged streaks.
    private static let flareHalfWidth: Double = 2.8
    /// Falloff radius (in cells) for ripple rings. Same idea as
    /// flareHalfWidth but for the circular pulse.
    private static let rippleHalfWidth: Double = 2.8

    private func draw(ctx: GraphicsContext, size: CGSize, time: Date) {
        let t = time.timeIntervalSinceReferenceDate
        let cols = Int(ceil(size.width / Self.pitch)) + 1
        let rows = Int(ceil(size.height / Self.pitch)) + 1
        let activeFlares = flares.filter {
            let age = t - $0.spawnEpoch
            return age >= 0 && t <= $0.expiresEpoch
        }
        let activeRipples = ripples.filter {
            let age = t - $0.spawnEpoch
            return age >= 0 && age <= $0.lifeSec
        }
        // Most cells are showing the same base L/chroma with only a
        // slightly different hue. Quantizing that decorative drift to 2°
        // lets a frame reuse a few dozen converted Colors instead of doing
        // a full OKLCh→sRGB conversion for every cell.
        var baseColorCache: [Int: Color] = [:]

        for r in 0..<rows {
            for c in 0..<cols {
                let base = baseColor(col: c, row: r, t: t)
                // Split contributions so flares can "cut through"
                // ripples where they overlap — the final boost lets
                // the flare dominate and the ripple only fills in
                // the portion above the flare's own brightness.
                var flareBoost: Double = 0
                var rippleBoost: Double = 0
                /// Hue offset contributed by the brightest flare at
                /// this cell — applied below, weighted by flareBoost,
                /// so each flare tints the cells it lights without
                /// muddying cells untouched by any flare.
                var flareHueOffset: Double = 0

                for f in activeFlares {
                    let dt = t - f.spawnEpoch
                    if dt < 0 || t > f.expiresEpoch { continue }
                    // Soft end-of-life fade so the flare doesn't
                    // snap from ~11% brightness straight to 0 when
                    // it's pruned. Linear ramp across the final
                    // 2 s of life brings every contribution
                    // (trail + halo) to zero before the prune.
                    let fadeWindow = 2.0
                    let remaining = f.expiresEpoch - t
                    let lifeFade = remaining < fadeWindow
                        ? max(0.0, remaining / fadeWindow)
                        : 1.0
                    // Resolve the flare's actual axis + start
                    // position given the CURRENT grid dimensions.
                    // axisNorm is normalized 0..1 so it maps to a
                    // valid row/col on any device; start is always
                    // one offscreen cell (via -2 or axisLen+1), so
                    // flares enter from off the visible area and
                    // sweep across the full row/col regardless of
                    // screen size.
                    let resolvedAxis: Int
                    let axisLen: Int
                    let axisOffAxis: Int
                    let axisPos: Double
                    switch f.kind {
                    case .row:
                        resolvedAxis = Int(f.axisNorm * Double(rows)) % max(1, rows)
                        axisLen = cols
                        axisOffAxis = r - resolvedAxis
                        axisPos = Double(c)
                    case .col:
                        resolvedAxis = Int(f.axisNorm * Double(cols)) % max(1, cols)
                        axisLen = rows
                        axisOffAxis = c - resolvedAxis
                        axisPos = Double(r)
                    }
                    let startCell = f.direction > 0
                        ? -2.0
                        : Double(axisLen + 1)
                    // On-axis trail. Head moves from startCell in
                    // `direction`; a cell is lit only if the head
                    // has already reached its position.
                    if axisOffAxis == 0 {
                        let delta = (axisPos - startCell) / f.direction
                        if delta >= 0 {
                            let touchTime = delta / f.speed
                            let dtTouch = dt - touchTime
                            if dtTouch >= 0 {
                                let attack = min(1.0, dtTouch / 0.08)
                                let tailDecay = 2.2 / max(0.5, f.lifeSec)
                                let contrib = attack * exp(-dtTouch * tailDecay) * lifeFade
                                if contrib > flareBoost {
                                    flareBoost = contrib
                                    flareHueOffset = f.hueOffset
                                }
                            }
                        }
                    }
                    // Faint radial halo around the head.
                    let headPos = startCell + f.direction * dt * f.speed
                    let dAlongAxis = axisPos - headPos
                    let dPerp = Double(axisOffAxis)
                    let radial = hypot(dAlongAxis, dPerp)
                    let haloFalloff = max(0, 1 - radial / 3.0)
                    let haloContrib = 0.12 * haloFalloff * lifeFade
                    if haloContrib > flareBoost {
                        flareBoost = haloContrib
                        flareHueOffset = f.hueOffset
                    }
                }

                for rip in activeRipples {
                    let dt = t - rip.spawnEpoch
                    if dt < 0 || dt > rip.lifeSec { continue }
                    let env = envelope(dt: dt, life: rip.lifeSec)
                    let cx = rip.origin.x / Self.pitch
                    let cy = rip.origin.y / Self.pitch
                    let radius = dt * rip.speed
                    let distToCenter = hypot(Double(c) - cx, Double(r) - cy)
                    let ringDist = abs(distToCenter - radius)
                    let falloff = max(0, 1 - ringDist / Self.rippleHalfWidth)
                    // Ripples glow noticeably dimmer than flares so
                    // a finger-dragged streak reads as a gentle
                    // water-trail, not a series of bright flashes.
                    // `strength` lets flare wakes + collision
                    // impacts punch above the baseline.
                    rippleBoost = max(rippleBoost, 0.50 * rip.strength * falloff * env)
                }

                // Flare-through-ripple compositing: the flare's
                // brightness takes priority, and the ripple only
                // fills in the amount above what the flare already
                // contributes. Where the flare is brightest, the
                // ripple effectively disappears — the line cuts
                // cleanly through the water.
                let boost = max(flareBoost, rippleBoost * (1.0 - flareBoost))

                // "Current" wave — scales each cell up/down on a
                // traveling sine so the whole field breathes at a
                // slow pace. Phase varies by (col, row) so the wave
                // appears to move diagonally across the grid.
                //
                // Flares/ripples only BRIGHTEN cells; they no longer
                // grow them. A lit cell's footprint equals its
                // current wave-determined size, so the streak reads
                // as light moving across an unperturbed surface.
                let wavePhase = Double(c) * 0.22 + Double(r) * 0.18 + t * 1.1
                let waveScale = 1.0 + 0.22 * Foundation.sin(wavePhase)
                let clampedScale = max(0.0, min(1.45, waveScale))
                let drawPx = Self.cellPx * CGFloat(clampedScale)

                // Physical ripple displacement — each ripple pushes
                // cells radially outward/inward as its ring passes
                // through them. Contributions from every live
                // ripple sum linearly — that IS wave superposition:
                // peaks reinforce where rings are in phase and
                // cancel where they're in opposite phase. Wider
                // spread and higher amplitude than the prior pass
                // make the interference visible to the eye.
                // Flares now deform with the water instead of
                // cutting through — no flare dampen here.
                var rippleDx: CGFloat = 0
                var rippleDy: CGFloat = 0
                for rip in activeRipples {
                    let dt = t - rip.spawnEpoch
                    if dt < 0 || dt > rip.lifeSec { continue }
                    let env = envelope(dt: dt, life: rip.lifeSec)
                    let cx = rip.origin.x / Self.pitch
                    let cy = rip.origin.y / Self.pitch
                    let dxCells = Double(c) - cx
                    let dyCells = Double(r) - cy
                    let d = hypot(dxCells, dyCells)
                    if d < 0.01 { continue }
                    let radius = dt * rip.speed
                    let spread = 5.0
                    let ringProx = (d - radius) / spread
                    let gauss = exp(-ringProx * ringProx)
                    let amp = 5.0 * rip.strength * env * gauss
                        * Foundation.sin(ringProx * .pi * 2)
                    let dirX = dxCells / d
                    let dirY = dyCells / d
                    rippleDx += CGFloat(amp * dirX)
                    rippleDy += CGFloat(amp * dirY)
                }

                let boosted = OKLCh(
                    L: min(OK.lMax, base.L + 0.55 * boost),
                    c: min(OK.cMax, base.c + 0.05 * boost),
                    // Apply the dominant flare's hue offset scaled
                    // by its brightness — cells under a flare take
                    // on its color tint proportional to how lit
                    // they are. Off-flare cells stay at the grid's
                    // own base hue.
                    h: OK.normH(base.h + flareHueOffset * flareBoost)
                )
                let alpha = 0.20 + 0.75 * boost
                let xCenter = CGFloat(c) * Self.pitch + Self.pitch / 2
                let yCenter = CGFloat(r) * Self.pitch + Self.pitch / 2
                let rect = CGRect(
                    x: xCenter - drawPx / 2 + rippleDx,
                    y: yCenter - drawPx / 2 + rippleDy,
                    width: drawPx,
                    height: drawPx
                )
                let path = Path(roundedRect: rect, cornerRadius: drawPx * 0.22)
                let fillColor: Color
                if boost < 0.005 {
                    let hueBucket = Int((OK.normH(base.h) / 2.0).rounded())
                    if let cached = baseColorCache[hueBucket] {
                        fillColor = cached
                    } else {
                        let converted = OK.toColor(
                            OKLCh(L: base.L, c: base.c, h: Double(hueBucket) * 2.0),
                            opacity: 0.20
                        )
                        baseColorCache[hueBucket] = converted
                        fillColor = converted
                    }
                } else {
                    fillColor = OK.toColor(boosted, opacity: alpha)
                }
                ctx.fill(path, with: .color(fillColor))
            }
        }
    }

    /// The collision task needs the visible grid dimensions, but a Canvas
    /// draw closure must remain side-effect free. Geometry changes are the
    /// correct lifecycle boundary for updating this state.
    private func cacheGridSize(_ size: CGSize) {
        cachedCols = Int(ceil(size.width / Self.pitch)) + 1
        cachedRows = Int(ceil(size.height / Self.pitch)) + 1
    }

    /// Where along the axis the flare's head currently sits, in cells.
    /// Starts offscreen on the entering side so the pulse sweeps fully
    /// across and then off.
    private func flareHeadPosition(direction: Double, dt: Double,
                                    speed: Double, axisLen: Int) -> Double {
        if direction > 0 {
            return -2.0 + dt * speed
        } else {
            return Double(axisLen + 1) - dt * speed
        }
    }

    /// Ambient hue field. Per-cell increments are tiny so adjacent
    /// cells sit within a narrow hue band, and the entire grid
    /// shifts through the full spectrum via a brisk global drift —
    /// roughly one complete wheel revolution every 45 s, plenty fast
    /// to see the whole field slide from reds → greens → blues.
    private func baseColor(col: Int, row: Int, t: Double) -> OKLCh {
        // Full-spectrum unison drift: 8°/sec ⇒ 360° in 45 s.
        let globalDrift = t * 8.0
        // Small per-cell offsets so neighbors are close in hue. The
        // grid's visible spread at any moment is just a narrow band
        // (≈ 30–40° over a typical device), which the drift then
        // slides through every color in the spectrum.
        let h = hueSeed
            + globalDrift
            + Double(col) * 1.4
            + Double(row) * 0.9
            + sin(Double(col) * 0.22 + t * 0.35) * 6
            + cos(Double(row) * 0.18 + t * 0.28) * 5
        let wrapped = h.truncatingRemainder(dividingBy: 360)
        return OKLCh(
            L: 0.30,
            c: 0.09,
            h: wrapped < 0 ? wrapped + 360 : wrapped
        )
    }

    /// High attack, low exponential decay. 0 → 1 in `attackSec`, then
    /// gentle exponential falloff so the tail lingers long after the
    /// head has traveled off-axis.
    private func envelope(dt: Double, life: Double) -> Double {
        let attackSec = 0.08
        if dt < attackSec {
            return dt / attackSec
        }
        // Much softer decay than before — picks `life` so the tail is
        // still ~18% at end-of-life (exp(-2.2 * 1) ≈ 0.11, adjust for
        // attack offset below).
        let decayRate = 2.0 / max(0.1, life - attackSec)
        return exp(-(dt - attackSec) * decayRate)
    }

    // ─── Flare spawning ─────────────────────────────────────────────

    /// Build a flare. If `semitone` is provided the axis is chosen
    /// from the pitch (so musical motion correlates visually to axis
    /// movement); ambient flares pick randomly.
    private func randomFlare(now: Double, semitone: Int?) -> GridFlare {
        let kind: GridFlare.Kind = (semitone.map { $0 & 1 == 0 } ?? Bool.random())
            ? .row : .col
        // Position is always randomized — the same note can land on
        // any row/column so repeated pitches don't hit the same axis.
        let axisNorm = Double.random(in: 0..<1)
        let direction: Double = Bool.random() ? 1 : -1
        // Note-triggered flares: the scale degree within an octave
        // picks the speed so pitch correlates with visual velocity
        // (higher note → faster streak). Ambient flares still pick
        // uniformly.
        let speed: Double = {
            if let semi = semitone {
                let degree = ((semi % 12) + 12) % 12
                return 4.0 + (Double(degree) / 11.0) * 14.0
            }
            return Double.random(in: 4...18)
        }()
        let life = Double.random(in: 6.0...9.0)
        // Per-flare hue tint — distinct flares paint distinct
        // streaks. ±45° covers about a hue-bucket on either side
        // of the base, wide enough to read as "a different color"
        // without leaving the surrounding field's palette.
        let hueOffset = Double.random(in: -45.0...45.0)
        return GridFlare(
            kind: kind,
            axisNorm: axisNorm,
            direction: direction,
            speed: speed,
            spawnEpoch: now,
            lifeSec: life,
            expiresEpoch: now + life,
            hueOffset: hueOffset
        )
    }

    // ─── Flare collisions ──────────────────────────────────────

    /// Detect head-cell collisions between live flares. The impact is an
    /// additive accent only: neither original direction, speed, trail nor
    /// lifetime changes.
    private func resolveFlareCollisions(now: Double, cols: Int, rows: Int) {
        guard flares.count >= 2, cols > 0, rows > 0 else { return }
        // Work on a snapshot of resolved heads so we can detect
        // collisions without re-reading mutated state mid-scan.
        struct Head {
            let idx: Int
            let axis: Int
            let headPos: Double
            let row: Double
            let col: Double
        }
        var heads: [Head] = []
        heads.reserveCapacity(flares.count)
        for i in flares.indices {
            let f = flares[i]
            let dt = now - f.spawnEpoch
            if dt < 0 || now > f.expiresEpoch || f.hasCollided { continue }
            let axisLen = f.kind == .row ? cols : rows
            let resolvedAxis = Int(f.axisNorm * Double(f.kind == .row ? rows : cols))
                % max(1, f.kind == .row ? rows : cols)
            let startCell = f.direction > 0 ? -2.0 : Double(axisLen + 1)
            let headPos = startCell + f.direction * dt * f.speed
            // Only consider heads currently inside the visible
            // grid — a flare whose head is still off-screen or has
            // already exited isn't a candidate.
            let axisMax = Double(axisLen - 1)
            guard headPos >= 0, headPos <= axisMax else { continue }
            let row: Double = (f.kind == .row) ? Double(resolvedAxis) : headPos
            let col: Double = (f.kind == .row) ? headPos : Double(resolvedAxis)
            heads.append(Head(idx: i, axis: resolvedAxis,
                              headPos: headPos, row: row, col: col))
        }
        // Pair-wise check. Collision threshold: heads within 0.8
        // cells of each other (≈ one cell's diameter).
        var collided: Set<Int> = []
        for i in 0..<heads.count {
            if collided.contains(heads[i].idx) { continue }
            for j in (i + 1)..<heads.count {
                if collided.contains(heads[j].idx) { continue }
                let dRow = heads[i].row - heads[j].row
                let dCol = heads[i].col - heads[j].col
                if dRow * dRow + dCol * dCol > 0.64 { continue }
                // Collision: preserve both flare trajectories and add one
                // restrained impact at their midpoint.
                let idxA = heads[i].idx
                let idxB = heads[j].idx
                let midRow = (heads[i].row + heads[j].row) / 2
                let midCol = (heads[i].col + heads[j].col) / 2
                flares[idxA].hasCollided = true
                flares[idxB].hasCollided = true
                // Keep the impact readable without moving cells by
                // almost a full grid pitch. Skip the decorative ring
                // when the field is already busy rather than adding
                // more full-grid work to an overloaded frame.
                let screenX = CGFloat(midCol) * Self.pitch + Self.pitch / 2
                let screenY = CGFloat(midRow) * Self.pitch + Self.pitch / 2
                if ripples.count < 12 {
                    ripples.append(GridRipple(
                        origin: CGPoint(x: screenX, y: screenY),
                        speed: 4.5,
                        spawnEpoch: now,
                        lifeSec: 1.6,
                        strength: 1.4
                    ))
                }
                collided.insert(idxA)
                collided.insert(idxB)
                break
            }
        }
    }
}
