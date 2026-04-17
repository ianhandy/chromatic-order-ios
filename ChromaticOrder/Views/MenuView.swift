//  Main menu — black backdrop with colored gradient "snakes" drifting
//  horizontally and vertically across the screen, plus three lowercase
//  options (zen / challenge / options). Shown on app launch before
//  any puzzle is active; dismisses once the player picks a mode.
//
//  Snakes are decorative — each is a line of small rounded tiles
//  whose colors step through OKLCh using the same seed+delta rhythm
//  the generator uses for puzzle gradients, so the menu visually
//  previews what the game is about.

import SwiftUI

struct MenuView: View {
    @Bindable var game: GameState
    /// Set true once the player picks zen or challenge. Parent view
    /// hides the menu and shows ContentView when this flips.
    @Binding var started: Bool

    @State private var snakes: [MenuSnake] = []
    @State private var hueDrift: Double = 0
    @State private var accessibilityOpen = false
    @State private var galleryOpen = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                // Snake backdrop — sized from the geometry so tiles
                // scale on iPad (if we ever re-enable) without
                // hand-tuning. Placed behind the menu buttons.
                SnakeField(snakes: snakes, hueDrift: hueDrift, size: geo.size)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 6) {
                Spacer()
                Text("kroma")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-1)
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
        .onAppear {
            // Generate snakes once per view lifecycle so they don't
            // thrash on view rebuilds. Fresh set on each cold launch.
            if snakes.isEmpty {
                snakes = MenuSnake.generateField()
            }
            // Slow continuous hue drift — every snake cycles the same
            // offset so the field breathes as a whole, not as a bunch
            // of independent streams.
            withAnimation(.linear(duration: 45).repeatForever(autoreverses: false)) {
                hueDrift = 360
            }
        }
        .sheet(isPresented: $accessibilityOpen) {
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
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// ─── Snake model ─────────────────────────────────────────────────────

private struct MenuSnake: Identifiable {
    let id = UUID()
    enum Axis { case horizontal, vertical }
    let axis: Axis
    /// Position perpendicular to the snake's run, as a 0…1 fraction
    /// of the screen's short axis. Horizontal snake at 0.3 lives at
    /// y = 0.3 * screenHeight; vertical snake at 0.7 lives at
    /// x = 0.7 * screenWidth.
    let positionFraction: CGFloat
    /// Tile size — smaller than game cells so the snakes read as
    /// decor, not a real grid.
    let tilePx: CGFloat
    /// Base OKLCh colors; rendering applies hueDrift on top.
    let colors: [OKLCh]

    static func generateField() -> [MenuSnake] {
        // 4-6 snakes: mix of axes, positions spread so they don't
        // clump. Seed color picked from the usable band; step delta
        // signs + magnitudes vary so the field has both short-hop and
        // long-hop gradients in view.
        var snakes: [MenuSnake] = []
        for i in 0..<5 {
            let axis: Axis = i.isMultiple(of: 2) ? .horizontal : .vertical
            let length = Int.random(in: 12...22)
            let tilePx: CGFloat = CGFloat.random(in: 22...36)
            let seedL = 0.4 + Double.random(in: 0..<0.3)
            let seedC = 0.1 + Double.random(in: 0..<0.15)
            let seedH = Double.random(in: 0..<360)
            let dH = Double.random(in: 12...35) * (Bool.random() ? 1 : -1)
            let dL = Double.random(in: -0.015...0.015)
            let dC = Double.random(in: -0.012...0.012)
            let colors: [OKLCh] = (0..<length).map { idx in
                OKLCh(
                    L: max(OK.lMin + 0.02, min(OK.lMax - 0.02, seedL + dL * Double(idx))),
                    c: max(OK.cMin + 0.01, min(OK.cMax - 0.02, seedC + dC * Double(idx))),
                    h: OK.normH(seedH + dH * Double(idx))
                )
            }
            // Spread positions across the short axis.
            let frac = CGFloat(i + 1) / 6.0 + CGFloat.random(in: -0.06...0.06)
            snakes.append(MenuSnake(
                axis: axis,
                positionFraction: max(0.08, min(0.92, frac)),
                tilePx: tilePx,
                colors: colors
            ))
        }
        return snakes
    }
}

// ─── Rendering ───────────────────────────────────────────────────────

private struct SnakeField: View {
    let snakes: [MenuSnake]
    let hueDrift: Double
    let size: CGSize

    var body: some View {
        ForEach(snakes) { snake in
            SnakeRow(snake: snake, hueDrift: hueDrift, canvas: size)
        }
    }
}

private struct SnakeRow: View {
    let snake: MenuSnake
    let hueDrift: Double
    let canvas: CGSize

    var body: some View {
        // Lay out each tile manually so horizontal + vertical share
        // one code path. Spacing is a fraction of tilePx; tiles have
        // the same rounded-corner signature as the puzzle cells.
        let gap: CGFloat = 2
        let radius = snake.tilePx * 0.26
        ZStack(alignment: .topLeading) {
            ForEach(Array(snake.colors.enumerated()), id: \.offset) { (i, color) in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OK.toColor(driftedColor(color), opacity: 0.85))
                    .frame(width: snake.tilePx, height: snake.tilePx)
                    .position(tilePosition(index: i, gap: gap))
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    /// Shift the snake's hue by the global drift so the whole field
    /// cycles in unison. Drift is already in degrees (0…360) on a
    /// repeating animation, so modular add is enough.
    private func driftedColor(_ c: OKLCh) -> OKLCh {
        OKLCh(L: c.L, c: c.c, h: OK.normH(c.h + hueDrift))
    }

    private func tilePosition(index: Int, gap: CGFloat) -> CGPoint {
        let step = snake.tilePx + gap
        switch snake.axis {
        case .horizontal:
            // Start off-screen-left by half the snake's length so it
            // spans with some extending past the right edge — reads
            // as "continues beyond the frame."
            let totalLen = CGFloat(snake.colors.count) * step
            let startX = (canvas.width - totalLen) / 2
            let x = startX + step * CGFloat(index) + snake.tilePx / 2
            let y = canvas.height * snake.positionFraction
            return CGPoint(x: x, y: y)
        case .vertical:
            let totalLen = CGFloat(snake.colors.count) * step
            let startY = (canvas.height - totalLen) / 2
            let y = startY + step * CGFloat(index) + snake.tilePx / 2
            let x = canvas.width * snake.positionFraction
            return CGPoint(x: x, y: y)
        }
    }
}
