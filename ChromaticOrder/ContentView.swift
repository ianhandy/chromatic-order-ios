//  Root view. Holds GameState, lays out the top bar / grid / bank, and
//  renders the modal overlays (edge vignette, menu, solved flash).

import SwiftUI

struct ContentView: View {
    @State private var game = GameState()
    @State private var menuOpen: Bool = false
    @State private var creatorOpen: Bool = false
    @State private var feedbackOpen: Bool = false

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
                        .padding(.horizontal, 22)
                    GridView(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 22)
                    BankView(game: game)
                        .padding(.horizontal, 22)
                }
                .padding(.vertical, 4)
            }

            // Edge vignette — viewport-level, above content.
            EdgeVignetteView(color: game.heldColor,
                             reduceMotion: game.reduceMotion)
                .allowsHitTesting(false)

            // Hamburger menu dropdown.
            if menuOpen {
                MenuSheet(game: game,
                          menuOpen: $menuOpen,
                          creatorOpen: $creatorOpen,
                          feedbackOpen: $feedbackOpen)
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

            // Dragged swatch ghost. Floats ABOVE the finger (not under)
            // so the dragged tile stays visible and isn't occluded by
            // the player's thumb. If magnetism has snapped to a cell,
            // pull toward that cell's center so the tug is visible
            // before release.
            if let src = game.dragSource, let loc = game.dragLocation {
                // Same lift constant used by GameState's hit-test — the
                // visible ghost and the effective drop point stay in sync.
                let lifted = CGPoint(x: loc.x, y: loc.y - GameState.ghostLift)
                let magnetized: CGPoint = {
                    let rect: CGRect? = {
                        switch game.dropTarget {
                        case .cell(let idx): return game.cellFrames[idx]
                        case .slot(let s):   return game.bankSlotFrames[s]
                        case .none:          return nil
                        }
                    }()
                    if let rect {
                        let target = CGPoint(x: rect.midX, y: rect.midY)
                        return CGPoint(
                            x: lifted.x + (target.x - lifted.x) * 0.30,
                            y: lifted.y + (target.y - lifted.y) * 0.30
                        )
                    }
                    return lifted
                }()
                DragGhost(color: src.color, location: magnetized)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if menuOpen { menuOpen = false }
            else if game.selection != nil { game.clearSelection() }
        }
        .animation(.easeOut(duration: 0.38), value: game.solved)
        .fullScreenCover(isPresented: $creatorOpen) {
            CreatorView(game: game)
        }
        .sheet(isPresented: $feedbackOpen) {
            FeedbackSheet(game: game)
        }
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
            // Smooth spring when the magnetism kicks in so the pull
            // toward the target cell reads as a subtle tug rather than
            // a teleport. Duration is short so rapid finger motion
            // still tracks.
            .animation(.spring(response: 0.15, dampingFraction: 0.85), value: location)
    }
}

#Preview {
    ContentView()
}
