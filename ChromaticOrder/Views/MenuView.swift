//  Main menu — black backdrop with a full-coverage grid of muted
//  color tiles. Each tile's hue/luminance/opacity is a sum-of-sines
//  function of (x, y, time), so the field undulates as overlapping
//  waves: color ripples diagonally across the grid, opacity breathes
//  in and out so whole regions gently fade into view and drift away.
//  The wordmark + menu buttons sit above with radial dims so the
//  letterforms stay readable over whatever wave is passing underneath.

import SwiftUI

struct MenuView: View {
    @Bindable var game: GameState
    /// Set true once the player picks zen or challenge. Parent view
    /// hides the menu and shows ContentView when this flips.
    @Binding var started: Bool

    @State private var accessibilityOpen = false
    @State private var galleryOpen = false
    /// Random hue anchor chosen on first appear — lets the wave field
    /// look different across cold launches without per-frame jitter.
    @State private var hueSeed: Double = Double.random(in: 0..<360)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                WaveGridField(hueSeed: hueSeed, size: geo.size)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 6) {
                Spacer()
                Text("kroma")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .tracking(-1)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    // Soft radial dim behind the wordmark so whatever
                    // wave is passing through doesn't chop the
                    // letterforms. Feathered edge keeps it feeling
                    // part of the composition, not a box.
                    .background(
                        RadialGradient(
                            colors: [Color.black.opacity(0.78), Color.black.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 140
                        )
                        .blendMode(.plusDarker)
                    )
                    .padding(.bottom, 40)
                menuButton("zen") {
                    pick(mode: .zen)
                }
                menuButton("challenge") {
                    pick(mode: .challenge)
                }
                menuButton("gallery") {
                    galleryOpen = true
                }
                menuButton("options") {
                    accessibilityOpen = true
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
        .sheet(isPresented: $accessibilityOpen, onDismiss: {
            // Persist + regen-if-changed. Without this, settings
            // adjusted from the main menu live only in memory and
            // revert on next launch.
            game.applyAccessibilityIfChanged()
        }) {
            AccessibilitySheet(game: game)
        }
        .sheet(isPresented: $galleryOpen) {
            GalleryView(game: game, started: $started)
        }
    }

    private func pick(mode: GameMode) {
        // switchMode is a toggle — only fire it when the current mode
        // doesn't already match the pick. Handles the mode's save +
        // challenge-mode check-count reset in one call.
        if game.mode != mode { game.switchMode() }
        withAnimation(.easeOut(duration: 0.35)) {
            started = true
        }
    }

    @ViewBuilder
    private func menuButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                // Semi-opaque black backdrop so the tile waves don't
                // chew through button text. No outline — the label
                // reads cleanly against the dim alone.
                .background(
                    Color.black.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .buttonStyle(.plain)
    }
}

// ─── Rendering ───────────────────────────────────────────────────────

private struct WaveGridField: View {
    let hueSeed: Double
    let size: CGSize

    var body: some View {
        // TimelineView drives per-frame redraws. Canvas renders all
        // grid tiles in one pass — ForEach(Rectangle) with 500+ cells
        // would choke the diff; Canvas stays smooth.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, canvasSize in
                drawField(context: context, size: canvasSize, time: timeline.date)
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Fixed grid — tile size is constant so the layout doesn't
    /// reshape when the canvas does. Tiles pad outside the visible
    /// bounds so waves entering/leaving the edges don't pop.
    private let tilePx: CGFloat = 26
    private let gap: CGFloat = 2

    private func drawField(context: GraphicsContext, size: CGSize, time: Date) {
        let step = tilePx + gap
        let cols = Int(ceil(size.width / step)) + 2
        let rows = Int(ceil(size.height / step)) + 2
        // Time in seconds — use a very small multiplier so the field
        // moves like drifting tides, not a spinning disco floor.
        let t = time.timeIntervalSinceReferenceDate * 0.22

        let radius = tilePx * 0.26
        for iy in 0..<rows {
            for ix in 0..<cols {
                let pos = tilePosition(ix: ix, iy: iy, step: step)
                // Cheap viewport cull — tiles fully outside the
                // canvas contribute nothing visible.
                if pos.x < -tilePx || pos.x > size.width + tilePx { continue }
                if pos.y < -tilePx || pos.y > size.height + tilePx { continue }
                let (color, alpha) = waveSample(ix: ix, iy: iy, t: t)
                guard alpha > 0.02 else { continue }
                let rect = CGRect(
                    x: pos.x - tilePx / 2,
                    y: pos.y - tilePx / 2,
                    width: tilePx, height: tilePx
                )
                let path = Path(roundedRect: rect, cornerRadius: radius)
                context.fill(path, with: .color(OK.toColor(color, opacity: alpha)))
            }
        }
    }

    private func tilePosition(ix: Int, iy: Int, step: CGFloat) -> CGPoint {
        // Shift by one step so the padded tiles tile around the edges
        // without a visible seam.
        CGPoint(
            x: step * CGFloat(ix - 1) + tilePx / 2,
            y: step * CGFloat(iy - 1) + tilePx / 2
        )
    }

    /// Sum-of-sines wave field. Three layers at different scales and
    /// angles produce smooth diagonal ripples that don't repeat
    /// visibly. Output is a low-L / low-c OKLCh color plus an
    /// opacity that also undulates so regions breathe in and out.
    private func waveSample(ix: Int, iy: Int, t: Double) -> (OKLCh, Double) {
        let x = Double(ix), y = Double(iy)

        // Three orthogonal-ish wave systems for the color field.
        let wA = sin(0.26 * x + 0.38 * y + t * 0.85)
        let wB = sin(0.19 * x - 0.30 * y + t * 0.55)
        let wC = sin(0.11 * x + 0.12 * y + t * 0.32)

        // Hue drifts around the seed anchor. Large amplitude so the
        // field spans real color variety, but the seed keeps each
        // launch visually distinct.
        let hue = OK.normH(hueSeed + 90 * wA + 55 * wB + 25 * wC)
        // Luminance stays low — "muted, smoky" band used before.
        let L = max(OK.lMin + 0.02, min(OK.lMax - 0.02, 0.30 + 0.06 * wC))
        // Chroma also stays low; tiny wobble adds texture without
        // pushing into loud territory.
        let c = max(OK.cMin + 0.005, min(OK.cMax - 0.01, 0.06 + 0.03 * wA))

        // Separate opacity wave — different angle + phase so the
        // breathing doesn't sync with the color motion. Range
        // [0.08, 0.78] so areas fully fade out yet never quite
        // vanish — keeps the backdrop alive.
        let wO = sin(0.18 * x + 0.24 * y + t * 0.40 + 1.7)
        let alpha = 0.08 + 0.35 * (wO * 0.5 + 0.5)

        return (OKLCh(L: L, c: c, h: hue), alpha)
    }
}
