//  Root view. Holds GameState, lays out the top bar / grid / bank, and
//  renders the modal overlays (edge vignette, menu, solved flash).

import SwiftUI

struct ContentView: View {
    @State private var game = GameState()
    @State private var menuOpen: Bool = false

    var body: some View {
        ZStack {
            Color(red: 0xfa / 255, green: 0xf8 / 255, blue: 0xf5 / 255)
                .ignoresSafeArea()

            if game.generating || game.puzzle == nil {
                VStack {
                    ProgressView("Building puzzle…")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tint(.gray)
                }
            } else {
                VStack(spacing: 0) {
                    TopBarView(game: game, menuOpen: $menuOpen)
                    GridView(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    BankView(game: game)
                }
            }

            // Edge vignette — viewport-level, above content.
            EdgeVignetteView(color: game.heldColor,
                             reduceMotion: game.reduceMotion)
                .allowsHitTesting(false)

            // Hamburger menu dropdown.
            if menuOpen {
                MenuSheet(game: game, menuOpen: $menuOpen)
            }

            // Floating Next Level button on solved.
            if game.solved, let _ = game.puzzle {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            game.handleNext()
                        } label: {
                            Text("Next Level \u{2192}")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .padding(.horizontal, 22)
                                .frame(height: 48)
                                .background(Color(red: 42 / 255, green: 157 / 255, blue: 78 / 255))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(color: Color(red: 42 / 255, green: 157 / 255, blue: 78 / 255).opacity(0.38),
                                        radius: 20, y: 6)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
                .transition(.opacity)
            }

            // Dragged swatch ghost.
            if let src = game.dragSource, let loc = game.dragLocation {
                DragGhost(color: src.color, location: loc)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if menuOpen { menuOpen = false }
            else if game.selection != nil { game.clearSelection() }
        }
        .animation(.easeOut(duration: 0.38), value: game.solved)
    }
}

private struct DragGhost: View {
    let color: OKLCh
    let location: CGPoint
    var body: some View {
        let px: CGFloat = 56
        RoundedRectangle(cornerRadius: px * 0.28, style: .continuous)
            .fill(OK.toColor(color))
            .frame(width: px, height: px)
            .scaleEffect(1.15)
            .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            .position(location)
    }
}

#Preview {
    ContentView()
}
