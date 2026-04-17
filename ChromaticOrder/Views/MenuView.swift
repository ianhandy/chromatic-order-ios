//  Main menu — black backdrop with muted gradient "snakes" sliding
//  slowly across the screen. Each snake enters from one edge, paints a
//  trailing row / column of low-saturation OKLCh tiles as its head
//  advances, and exits the opposite edge. A regeneration loop spawns
//  new snakes as old ones finish so the backdrop stays alive.
//
//  Snakes are decorative — each is a line of small rounded tiles whose
//  colors step through OKLCh using the same seed+delta rhythm the
//  generator uses for puzzle gradients, so the menu visually previews
//  what the game is about.

import SwiftUI

struct MenuView: View {
    @Bindable var game: GameState
    /// Set true once the player picks zen or challenge. Parent view
    /// hides the menu and shows ContentView when this flips.
    @Binding var started: Bool

    @State private var snakes: [MenuSnake] = []
    @State private var accessibilityOpen = false
    @State private var galleryOpen = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                // Snake backdrop — sized from the geometry so tiles
                // scale on iPad (if we ever re-enable) without
                // hand-tuning. Placed behind the menu buttons.
                SnakeField(snakes: snakes, size: geo.size)
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
                    // Soft radial dim behind the wordmark so the
                    // snake tiles don't chop the letterforms — black
                    // core with a feathered edge keeps it feeling
                    // like part of the composition, not a box.
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
        .task { await runSnakeLoop() }
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
                // Semi-opaque black backdrop so the snake tiles don't
                // chew through button text. No outline — the label
                // reads cleanly against the dim alone.
                .background(
                    Color.black.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .buttonStyle(.plain)
    }

    /// Regeneration loop — seeds snakes on first run, then wakes every
    /// ~750ms to respawn any snake whose lifecycle has ended. Driven
    /// from `.task` so it cancels cleanly when the view goes away.
    @MainActor
    private func runSnakeLoop() async {
        if snakes.isEmpty {
            snakes = (0..<6).map { _ in
                // Stagger births so the initial field has snakes at
                // different lifecycle phases instead of all entering
                // in lockstep.
                let offset = Double.random(in: -15...0)
                return MenuSnake.random(born: Date().addingTimeInterval(offset))
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(750))
            let now = Date()
            for i in snakes.indices {
                if now.timeIntervalSince(snakes[i].birth) > snakes[i].lifespan {
                    snakes[i] = MenuSnake.random(born: now)
                }
            }
        }
    }
}

// ─── Snake model ─────────────────────────────────────────────────────

struct MenuSnake: Identifiable {
    let id = UUID()
    enum Axis { case horizontal, vertical }
    let axis: Axis
    /// +1 = moves in the axis's positive direction (left→right or
    /// top→bottom); -1 reverses. Randomized per spawn.
    let direction: Int
    /// Perpendicular position as a 0…1 fraction of the canvas's other
    /// axis. A horizontal snake at 0.3 runs at y = 0.3 * height.
    let positionFraction: CGFloat
    let tilePx: CGFloat
    /// OKLCh gradient params. Colors are computed on demand from these
    /// — low L / low c / randomized starting hue for a muted, smoky
    /// backdrop that doesn't fight the menu text.
    let baseHue: Double
    let stepH: Double
    let baseL: Double
    let stepL: Double
    let baseC: Double
    let stepC: Double
    let birth: Date
    /// Seconds for the head to travel from the origin edge across the
    /// canvas. "Slowly" means this is long — the snake spends most of
    /// its life crawling.
    let drawDuration: Double
    let holdDuration: Double
    let fadeDuration: Double
    var lifespan: Double { drawDuration + holdDuration + fadeDuration }

    func color(at index: Int) -> OKLCh {
        OKLCh(
            L: max(OK.lMin + 0.02, min(OK.lMax - 0.04, baseL + stepL * Double(index))),
            c: max(OK.cMin + 0.005, min(OK.cMax - 0.02, baseC + stepC * Double(index))),
            h: OK.normH(baseHue + stepH * Double(index))
        )
    }

    static func random(born: Date) -> MenuSnake {
        MenuSnake(
            axis: Bool.random() ? .horizontal : .vertical,
            direction: Bool.random() ? 1 : -1,
            positionFraction: CGFloat.random(in: 0.08...0.92),
            tilePx: CGFloat.random(in: 20...32),
            baseHue: Double.random(in: 0..<360),
            stepH: Double.random(in: 6...20) * (Bool.random() ? 1 : -1),
            // Low brightness — lMin is 0.24, clamp near that range so
            // the snakes read as shadowy trails, not loud stripes.
            baseL: 0.26 + Double.random(in: 0..<0.12),
            stepL: Double.random(in: -0.006...0.006),
            // Low saturation — stays under 0.1 chroma so colors feel
            // muted / washed, not poster-bright.
            baseC: 0.04 + Double.random(in: 0..<0.05),
            stepC: Double.random(in: -0.004...0.004),
            birth: born,
            // Long draw time — ~20 seconds for a head to cross the
            // screen feels "slow, drifting" rather than urgent.
            drawDuration: Double.random(in: 18...28),
            holdDuration: Double.random(in: 2...4),
            fadeDuration: Double.random(in: 3...5)
        )
    }
}

// ─── Rendering ───────────────────────────────────────────────────────

private struct SnakeField: View {
    let snakes: [MenuSnake]
    let size: CGSize

    var body: some View {
        // TimelineView drives per-frame redraws from a single place —
        // Canvas draws all tiles in one pass, much cheaper than
        // ForEach(RoundedRectangle) when we have 100+ cells on screen.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, canvasSize in
                let now = timeline.date
                for snake in snakes {
                    draw(snake: snake, at: now, in: context, size: canvasSize)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private func draw(snake: MenuSnake, at now: Date, in context: GraphicsContext, size: CGSize) {
        let elapsed = now.timeIntervalSince(snake.birth)
        guard elapsed >= 0 else { return }

        let step = snake.tilePx + 2
        let axisExtent: CGFloat = snake.axis == .horizontal ? size.width : size.height
        // Virtual length — number of tile positions spanning the
        // canvas plus a buffer on each side so the head enters from
        // off-screen and exits off-screen.
        let buffer = 6
        let spanTiles = max(1, Int(ceil(axisExtent / step)))
        let totalTiles = spanTiles + buffer * 2

        let drawProgress = max(0, min(1, elapsed / snake.drawDuration))
        let visible = Int(floor(drawProgress * Double(totalTiles)))
        guard visible > 0 else { return }

        let fadePhase = max(0, elapsed - snake.drawDuration - snake.holdDuration)
        let alpha = fadePhase > 0 ? max(0, 1 - fadePhase / snake.fadeDuration) : 1
        let radius = snake.tilePx * 0.26
        let perpPos: CGFloat = snake.axis == .horizontal
            ? size.height * snake.positionFraction
            : size.width * snake.positionFraction

        // Each tile's along-axis position is `step * i` measured from
        // the origin edge minus the buffer (so i=0 sits just outside
        // the origin edge, entering the frame as drawProgress grows).
        for i in 0..<visible {
            let alongAxis = step * CGFloat(i - buffer) + snake.tilePx / 2
            let pos: CGPoint
            switch snake.axis {
            case .horizontal:
                let x = snake.direction > 0 ? alongAxis : (size.width - alongAxis)
                pos = CGPoint(x: x, y: perpPos)
            case .vertical:
                let y = snake.direction > 0 ? alongAxis : (size.height - alongAxis)
                pos = CGPoint(x: perpPos, y: y)
            }
            let rect = CGRect(
                x: pos.x - snake.tilePx / 2,
                y: pos.y - snake.tilePx / 2,
                width: snake.tilePx,
                height: snake.tilePx
            )
            // Skip tiles fully outside the canvas — Canvas clips them
            // anyway but avoiding the fill call keeps GPU work down.
            guard rect.maxX > -snake.tilePx, rect.minX < size.width + snake.tilePx,
                  rect.maxY > -snake.tilePx, rect.minY < size.height + snake.tilePx
            else { continue }
            let path = Path(roundedRect: rect, cornerRadius: radius)
            let color = snake.color(at: i)
            context.fill(path, with: .color(OK.toColor(color, opacity: 0.82 * alpha)))
        }
    }
}
