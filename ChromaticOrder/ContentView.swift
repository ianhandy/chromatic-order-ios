//  Root view. Holds GameState, lays out the top bar / grid / bank, and
//  renders the modal overlays (edge vignette, menu, solved flash).

import SwiftUI

struct ContentView: View {
    /// Shared GameState instance — owned by ChromaticOrderApp so the
    /// MenuView and ContentView play against the same state (so mode
    /// picks made on the menu land on the same game). Declared as
    /// @Bindable because @State would make a private copy.
    @Bindable var game: GameState
    @State private var menuOpen: Bool = false
    @State private var creatorOpen: Bool = false
    @State private var feedbackOpen: Bool = false
    @State private var accessibilityOpen: Bool = false
    /// Set by ChromaticOrderApp.onOpenURL when a .kroma file is tapped.
    /// We watch it and pipe the Puzzle into the game when it changes.
    @Binding var incomingPuzzle: Puzzle?
    /// Flipped back to false by the hamburger "Back to Menu" action so
    /// the app returns to MenuView without unloading GameState.
    @Binding var started: Bool

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
                        BankView(game: game)
                            .padding(.horizontal, 22)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .bottom))))
                    }
                }
                .padding(.vertical, 4)
            }

            OnboardingOverlay(game: game)

            // Edge vignette — viewport-level, above content. Gated
            // on the Accessibility toggle so players who find the
            // color halo distracting can disable it.
            if game.edgeVignetteEnabled {
                EdgeVignetteView(color: game.heldColor,
                                 reduceMotion: game.reduceMotion)
                    .allowsHitTesting(false)
            }

            // Hamburger menu — always mounted so the close animation
            // (labels fade, icons retract off-screen) can play out.
            // Internal `menuOpen` state gates hit-testing so the menu
            // doesn't eat taps on the game while closed.
            MenuSheet(game: game,
                      menuOpen: $menuOpen,
                      creatorOpen: $creatorOpen,
                      feedbackOpen: $feedbackOpen,
                      accessibilityOpen: $accessibilityOpen,
                      started: $started)

            // Solved overlay: Like widget on the bottom-left, Next
            // Level button on the bottom-right. The widget only shows
            // after a solve — asking "did you like THIS level?" is
            // only meaningful once the player has actually finished it.
            if game.solved, let _ = game.puzzle {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        LikeFeedbackWidget(game: game)
                            .padding(.leading, 20)
                            .padding(.bottom, 20)
                        Spacer()
                        Button {
                            if let p = game.puzzle {
                                presentSolvedShare(puzzle: p, level: game.level)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 22)
                        Button {
                            game.handleNext()
                        } label: {
                            Text("next level \u{2192}")
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

            // Dragged swatch ghost. Always floats at the lifted
            // position above the finger so the player can see the
            // color they're holding, even when magnetism has locked
            // onto a cell below. The targeted cell still gets its
            // drop-tint (rendered inside CellView) — now two visual
            // cues: tint where it will land, swatch in hand above
            // finger so the color never hides under a thumb.
            if let src = game.dragSource, let loc = game.dragLocation {
                let lifted = CGPoint(x: loc.x, y: loc.y - game.ghostLift)
                DragGhost(color: src.color, location: lifted)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if menuOpen { menuOpen = false }
            else if game.selection != nil { game.clearSelection() }
        }
        .onShake {
            // Shake to shuffle — replaces the old bottom-right reset
            // button. Only acts on an in-progress puzzle so a shake
            // during the solved overlay doesn't wipe the win state.
            if !game.solved, game.puzzle != nil {
                Haptics.shake()
                game.handleReset()
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: game.solved)
        .onChange(of: incomingPuzzle != nil) { _, hasIncoming in
            if hasIncoming { loadIncomingPuzzleIfAny() }
        }
        .onAppear {
            GlassyAudio.shared.startMusicIfNeeded()
            // ContentView mounts AFTER Universal Link / kroma:// handlers
            // may have set incomingPuzzle during a cold launch. onChange
            // only fires on subsequent transitions, so check on appear
            // too to catch the mount-already-set case.
            loadIncomingPuzzleIfAny()
        }
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
        .sheet(isPresented: $accessibilityOpen, onDismiss: {
            // Deferred regeneration: contrast + clamp sliders move
            // during the sheet but the board doesn't rebuild until
            // the player closes the sheet — applyAccessibilityIfChanged
            // compares current values to those-at-last-generation and
            // triggers startLevel only when needed.
            game.applyAccessibilityIfChanged()
        }) {
            AccessibilitySheet(game: game)
        }
    }

    /// Unified loader for externally-supplied puzzles (.kroma file tap,
    /// kroma:// scheme, Universal Link). Clears any open sheets and
    /// hands the puzzle to GameState, then resets the binding so the
    /// same puzzle doesn't re-trigger on a later backgrounding.
    private func loadIncomingPuzzleIfAny() {
        guard let puzzle = incomingPuzzle else { return }
        game.loadCustomPuzzle(puzzle)
        creatorOpen = false
        feedbackOpen = false
        menuOpen = false
        incomingPuzzle = nil
    }
}

private struct DragGhost: View {
    let color: OKLCh
    let location: CGPoint
    var body: some View {
        let size: CGFloat = 56
        let radius = size * 0.28
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OK.toColor(color))
            .frame(width: size, height: size)
            .scaleEffect(1.15)
            .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            .position(location)
            .animation(.spring(response: 0.20, dampingFraction: 0.78), value: location)
    }
}

#Preview {
    ContentView(game: GameState(),
                incomingPuzzle: .constant(nil),
                started: .constant(true))
}
