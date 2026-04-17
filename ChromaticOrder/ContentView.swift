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
            Color.black
                .ignoresSafeArea()

            if game.generating || game.puzzle == nil {
                VStack {
                    ProgressView("Building puzzle…")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                VStack(spacing: 0) {
                    TopBarView(game: game, menuOpen: $menuOpen)
                        .padding(.horizontal, 22)
                    GridView(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 22)
                    // Bank slides out on solve so the solved grid can
                    // breathe; returns when handleNext loads a fresh
                    // puzzle. Gentle spring matches the .solved transition
                    // applied to the whole ZStack below.
                    if !game.solved {
                        // Quick like/dislike widget, right-aligned just
                        // above the bank. "Bottom right corner" for the
                        // play area without overlapping swatches — the
                        // bank itself lives below it. Hidden on solve.
                        HStack {
                            Spacer()
                            LikeFeedbackWidget(game: game)
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 4)
                        BankView(game: game)
                            .padding(.horizontal, 22)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))))
                    }
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
                let targetRect: CGRect? = {
                    switch game.dropTarget {
                    case .cell(let idx): return game.cellFrames[idx]
                    case .slot(let s):   return game.bankSlotFrames[s]
                    case .none:          return nil
                    }
                }()
                // Suck-in: when a drop target is locked, the ghost
                // snaps to that cell's position AND size — it becomes
                // the cell visually. On release, the placement lands
                // in the cell the ghost is sitting on, matching what
                // the player sees. When magnetism drops (finger moves
                // off), the ghost springs back to floating-above-finger
                // size — the "spit out" feeling.
                let magnetized = targetRect.map {
                    CGPoint(x: $0.midX, y: $0.midY)
                } ?? lifted
                let targetSize = targetRect?.size
                DragGhost(color: src.color, location: magnetized, snapSize: targetSize)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if menuOpen { menuOpen = false }
            else if game.selection != nil { game.clearSelection() }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: game.solved)
        .onChange(of: menuOpen) { _, isOpen in
            // Deferred CB regeneration: cycling the CB mode inside
            // the menu updates game.cbMode but doesn't rebuild the
            // puzzle — that'd thrash the board mid-cycle. When the
            // menu closes, check whether the chosen mode differs
            // from what the current puzzle was generated under and
            // rebuild only if so.
            if !isOpen { game.applyDeferredCBModeChange() }
        }
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
    /// When non-nil, magnetism has locked onto a cell. The ghost
    /// shrinks to that cell's size, drops its shadow, and fades out —
    /// the target cell's drop-tint takes over as the visual so the
    /// color doesn't double-render (once in the hand, once in the
    /// cell). When demagnetized, the ghost fades back in at its
    /// floating-above-finger size.
    let snapSize: CGSize?
    var body: some View {
        let defaultPx: CGFloat = 56
        let size = snapSize ?? CGSize(width: defaultPx, height: defaultPx)
        let radius = min(size.width, size.height) * 0.28
        let isMagnetized = snapSize != nil
        let scale: CGFloat = isMagnetized ? 1.0 : 1.15
        let opacity: Double = isMagnetized ? 0.0 : 1.0
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(color))
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .shadow(color: .black.opacity(isMagnetized ? 0.0 : 0.22),
                    radius: isMagnetized ? 0 : 12,
                    y: isMagnetized ? 0 : 6)
            .opacity(opacity)
            .position(location)
            // Snappy spring for position + size; slightly longer
            // opacity fade so the ghost visibly "sucks into" the cell
            // before disappearing (shrinks + fades as the cell tint
            // swells in underneath).
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: location)
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: size.width)
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: size.height)
            .animation(.easeOut(duration: 0.20), value: isMagnetized)
    }
}

#Preview {
    ContentView()
}
