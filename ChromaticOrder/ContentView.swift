//  Root view. Holds GameState, lays out the top bar / grid / bank, and
//  renders the modal overlays (edge vignette, menu, solved flash).

import SwiftUI
import Photos

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
    @State private var communityOpen: Bool = false
    /// Set by ChromaticOrderApp.onOpenURL when a .kroma file is tapped.
    /// We watch it and pipe the Puzzle into the game when it changes.
    @Binding var incomingPuzzle: Puzzle?
    /// Flipped back to false by the hamburger "Back to Menu" action so
    /// the app returns to MenuView without unloading GameState.
    @Binding var started: Bool
    @Environment(Transitioner.self) private var transitioner
    /// Shows the "perfect" banner briefly after a perfect solve.
    /// Flips true on each fresh perfect solve, then fades away after
    /// ~1 s — the banner is a celebratory flash, not a persistent
    /// label while the solved overlay is up.
    @State private var perfectBannerVisible: Bool = false
    /// Namespace shared with TopBarView so the perfect-solve heart can
    /// matched-geometry-fly from the "perfect" banner down into the
    /// top-bar hearts row.
    @Namespace private var perfectHeartNS
    /// Choreography for the celebratory perfect-solve heart — see
    /// `PerfectHeartStage` for the stage ordering.
    @State private var perfectHeartStage: PerfectHeartStage = .idle
    /// Handle for the in-flight perfect-heart animation task so
    /// `handleNext` (or any other level-advance) can cancel it before
    /// the delayed `game.checks += 1` fires. Without cancellation the
    /// task wakes up on the next level and double-counts when
    /// combined with handleNext's own perfect-solve award.
    @State private var perfectHeartFlightTask: Task<Void, Never>? = nil
    /// Bumped when the flying heart lands so TopBarView can kick off
    /// its per-heart scale-bump wave.
    @State private var heartWaveTick: Int = 0
    /// Bumped every time a new pop burst is triggered so the
    /// particle overlay re-renders as a fresh view each time rather
    /// than trying to reuse stale particle state.
    @State private var popBurstTick: Int = 0
    /// Captured balloon-center screen position when the pop fires.
    /// Stored separately from the live anchor so particles can continue
    /// even after the balloon unmounts (which clears the anchor 0.11s
    /// after the pop but before the 2.2s particle animation ends).
    @State private var popBurstOriginCapture: CGPoint? = nil
    /// Most recent live balloon-center position resolved from the
    /// `balloonCenter` preference anchor. Updated every layout pass
    /// the balloon publishes it, so the pop handler can capture the
    /// origin synchronously on tap instead of racing the anchor
    /// against the .popped unmount animation.
    @State private var balloonCenterLive: CGPoint? = nil
    /// Tint snapshot for the most recent pop so the particle colors
    /// match the balloon the player just popped.
    @State private var popBurstTint: Color = .pink
    /// Active tutorial overlay, if any. Shown over the game view on
    /// first-time mode entries (challenge / zen / daily).
    @State private var tutorialFlag: TutorialFlag? = nil
    /// Exit choreography for the active tutorial balloon. `.alive`
    /// while it's on-screen; flips to `.released` on normal dismissal
    /// (menu open, level change, first placement) so the balloon
    /// floats away, or `.popped` when the player taps it for the
    /// quick pop animation. Parent unmounts the balloon only after
    /// the exit animation reports completion via `onFinished`.
    @State private var tutorialExit: TutorialBalloonExit = .alive
    /// Level captured when a zen tutorial tooltip appears; the
    /// tooltip auto-dismisses once the player uses the level picker
    /// (game.level changes).
    @State private var zenTutorialBaselineLevel: Int? = nil

    /// Scale applied to the grid on solve — shrinks to 0.85 then
    /// snaps back to 1.0 on the next quarter-note beat.
    @State private var solveSquishScale: CGFloat = 1.0
    /// Tri-state icon on the save-image button — neutral arrow by
    /// default, checkmark on success, xmark on failure. Resets back
    /// to neutral after a short delay.
    @State private var saveImageIconName: String = "square.and.arrow.down"

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Wrap the loading ⇄ playing swap in a single Group so
            // SwiftUI can crossfade between the two branches instead
            // of snapping. Each branch carries its own `.transition`
            // so the opacity animation attaches even when the other
            // side is unmounted. `puzzle?.level` is keyed too — so
            // going from level N's playing state to level N+1's
            // playing state (puzzle swaps in place) also fades,
            // preventing the "one board disappears, another appears
            // a frame later" pop the player sees at `handleNext`.
            Group {
                if game.generating {
                    VStack {
                        ProgressView("Building puzzle…")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .transition(.opacity)
                } else if game.puzzle == nil && game.mode == .daily && game.dailyUnavailable {
                    // Server hasn't published a daily for this UTC date
                    // (or the fetch failed outright). We don't fall back
                    // to local generation — every player must see the
                    // same daily — so render a tap-to-retry placeholder.
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("no daily yet")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Check back later — today's puzzle hasn't been published yet.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            game.startLevel(game.level)
                        } label: {
                            Text("Try again")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .frame(height: 38)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(.top, 4)
                    }
                    .transition(.opacity)
                } else if game.puzzle == nil {
                    VStack {
                        ProgressView("Building puzzle…")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tint(.white)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .transition(.opacity)
                } else {
                    playingContent
                        .id(game.puzzle?.level ?? 0)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: game.generating)
            .animation(.easeInOut(duration: 0.45), value: game.puzzle?.level)
            .animation(.easeInOut(duration: 0.45), value: game.dailyUnavailable)

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
                      communityOpen: $communityOpen,
                      started: $started)

            // Solved overlay: Like widget on the bottom-left, Next
            // Level button on the bottom-right. The widget only shows
            // after a solve — asking "did you like THIS level?" is
            // only meaningful once the player has actually finished it.
            if game.solved, let _ = game.puzzle {
                VStack(spacing: 14) {
                    Spacer()
                    if perfectBannerVisible || perfectHeartStage == .onBanner {
                        HStack(spacing: 16) {
                            if perfectBannerVisible {
                                Text("perfect")
                                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .tracking(2)
                                    .shadow(color: .white.opacity(0.35), radius: 18, y: 0)
                                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            }
                            // Banner-side placeholder of the matched
                            // heart. Same red as the top-bar hearts so
                            // the fly-transition lands on the exact
                            // final color without a crossfade.
                            if perfectHeartStage == .onBanner {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                                    .matchedGeometryEffect(
                                        id: "perfectHeart",
                                        in: perfectHeartNS,
                                        isSource: true
                                    )
                            }
                        }
                    }
                    // "good level?" + save-image + "next level" line up
                    // on one shared baseline. The two text-bearing
                    // affordances share `solvedRowHeight` so they read
                    // as a matched pair bracketing the icon-only save
                    // button in the middle.
                    let solvedRowHeight: CGFloat = 52
                    HStack(alignment: .center, spacing: 8) {
                        LikeFeedbackWidget(game: game,
                                           feedbackOpen: $feedbackOpen,
                                           height: solvedRowHeight)
                            .layoutPriority(1)
                        Button {
                            if let p = game.puzzle {
                                saveSolvedImage(puzzle: p)
                            }
                        } label: {
                            Image(systemName: saveImageIconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(width: solvedRowHeight,
                                       height: solvedRowHeight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save image")
                        Button {
                            game.handleNext()
                            // Daily is a single run per date — after
                            // submitting the score, take the player
                            // back to the menu rather than regenerating
                            // the same solved board in place.
                            if game.mode == .daily {
                                transitioner.fade { started = false }
                            }
                        } label: {
                            Text(game.mode == .daily
                                 ? "back to menu"
                                 : "next level")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 18)
                                .frame(height: solvedRowHeight)
                                .background(Color(red: 42 / 255, green: 157 / 255, blue: 78 / 255))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(color: Color(red: 42 / 255, green: 157 / 255, blue: 78 / 255).opacity(0.38),
                                        radius: 20, y: 6)
                        }
                        .buttonStyle(.plain)
                        .layoutPriority(1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
                .transition(.opacity)
            }

            // Focus dim — darkens the screen under every layer
            // below its zIndex while the daily show-answers inline
            // confirm is active. Tutorials deliberately do NOT
            // trigger the dim: the player needs to interact with the
            // board / bank while the tooltip is visible, and dimming
            // those made the UI they're supposed to practice on look
            // disabled. Tooltip legibility is handled by the
            // tooltip's own high-contrast background instead.
            FocusDim(active: game.dailyShowAnswersConfirmPending)
                .zIndex(18)

            // Daily leaderboard-warning dialog. Rides on the same
            // `dailyShowAnswersConfirmPending` flag as the FocusDim
            // behind it, so the card shows with the backdrop already
            // darkened. The card itself animates fold-up via a
            // combined scale+opacity transition; the transparent
            // backdrop inside the view catches outside taps (treated
            // as "no").
            if game.dailyShowAnswersConfirmPending {
                DailyLeaderboardWarningDialog(
                    onYes: {
                        withAnimation(.spring(response: 0.32,
                                              dampingFraction: 0.80)) {
                            game.toggleShowIncorrect()
                            game.dailyShowAnswersConfirmPending = false
                        }
                    },
                    onNo: {
                        withAnimation(.spring(response: 0.32,
                                              dampingFraction: 0.80)) {
                            game.dailyShowAnswersConfirmPending = false
                        }
                    }
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .zIndex(19)
            }

            // Tutorial tooltip — positioned per-mode so it lands in
            // the whitespace around the grid (not on top of the
            // color swatches it's describing). Challenge points at
            // the bank (bottom), so sit just above it. Zen/daily
            // point at the top-bar controls, so sit just below them.
            // Predetermined tutorial seeds (TutorialFlag.puzzleSeed)
            // keep the board layout stable so this positioning
            // actually clears the cells every time.
            if let flag = tutorialFlag {
                tutorialTooltipLayer(for: flag)
                    .zIndex(30)
                    .transition(.opacity)
                balloonStringOverlay
            }

            popBurstOverlay
                .zIndex(32)

            // Challenge run-over overlay. Fires when the player
            // loses their last heart in challenge mode. Covers the
            // screen with a dim + centered summary; tapping "back
            // to menu" fades out to MenuView, where the next
            // challenge entry calls enterMode and clears the flag.
            if game.runComplete {
                RunCompleteOverlay(levelsCompleted: game.challengeSolveCount) {
                    transitioner.fade { started = false }
                }
                .transition(.opacity)
                .zIndex(10)
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
        .animation(.easeInOut(duration: 0.7), value: perfectBannerVisible)
        .onChange(of: game.solved) { _, solvedNow in
            if solvedNow {
                // Squish → wait for next quarter-note beat → snap
                // back → chord + haptic. The visual "inhale" before
                // the chord makes the reward land harder.
                solveSquishScale = 0.85
                let delay = GlassyAudio.shared.secondsToNextQuarterBeat()
                // Floor at ~120ms so the squish is always visible
                let waitNs = UInt64(max(0.12, delay) * 1_000_000_000)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: waitNs)
                    solveSquishScale = 1.0
                    game.playSolveChord()
                    Haptics.solve()
                }
            }
            if solvedNow && game.isPerfectSolve {
                perfectBannerVisible = true
                perfectHeartStage = .onBanner
                // Cancel any still-running flight from a previous
                // solve before starting a new one — avoids the task
                // waking on the next level and stomping state.
                perfectHeartFlightTask?.cancel()
                perfectHeartFlightTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                    perfectBannerVisible = false
                    if game.mode == .challenge {
                        withAnimation(.spring(response: 0.7,
                                              dampingFraction: 0.75)) {
                            perfectHeartStage = .flying
                        }
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if Task.isCancelled { return }
                        // Claim-once token: if handleNext (fast Next
                        // tap) has already awarded the perfect heart
                        // it'll have set `perfectHeartAlreadyAwarded`
                        // to true — in that case we skip the +1 here
                        // and just finish the animation. Whichever
                        // path fires first wins; the other is a
                        // no-op. Clearing happens in startLevel so
                        // the next perfect solve can claim again.
                        if !game.perfectHeartAlreadyAwarded {
                            game.checks += 1
                            game.perfectHeartAlreadyAwarded = true
                        }
                        perfectHeartStage = .landed
                        try? await Task.sleep(nanoseconds: 34_000_000)
                        if Task.isCancelled { return }
                        heartWaveTick &+= 1
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        if Task.isCancelled { return }
                        perfectHeartStage = .idle
                    } else {
                        perfectHeartStage = .idle
                    }
                }
            } else if !solvedNow {
                perfectHeartFlightTask?.cancel()
                perfectHeartFlightTask = nil
                perfectBannerVisible = false
                perfectHeartStage = .idle
                solveSquishScale = 1.0
            }
        }
        .animation(.easeInOut(duration: 0.35), value: game.runComplete)
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
            maybeShowTutorialForCurrentMode()
        }
        .onChange(of: game.mode) { _, _ in
            maybeShowTutorialForCurrentMode()
        }
        .onChange(of: game.moveCount) { _, newCount in
            // Challenge + daily tutorials auto-dismiss on first
            // placement — the action the tooltip describes has been
            // performed, so the tip has served its purpose.
            if newCount > 0,
               tutorialFlag == .firstLaunch || tutorialFlag == .dailyIntro {
                releaseTutorial()
            }

        }
        .onChange(of: game.level) { _, _ in
            // Zen tutorial auto-dismisses once the player changes
            // level — the tooltip's point was "use the picker".
            if tutorialFlag == .zenIntro,
               let baseline = zenTutorialBaselineLevel,
               game.level != baseline {
                releaseTutorial()
            }
        }
        .onChange(of: menuOpen) { _, isOpen in
            // Opening the menu releases any active tutorial — the
            // player has moved on from the thing the tip pointed at.
            if isOpen {
                releaseTutorial()
            }
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
        .sheet(isPresented: $communityOpen) {
            CommunityListView(game: game)
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

    /// Auto-rotation caps — small enough that `rotation3DEffect` stays
    /// well inside the range where Core Animation's perspective matrix
    /// is numerically stable on older GPUs. Player-driven tilt has
    /// been removed entirely: it was producing extreme angles under
    /// drag and caused at least one on-device crash on the perspective
    /// path.
    private static let autoTiltMaxDegX: Double = 7
    private static let autoTiltMaxDegY: Double = 9
    /// Seconds over which auto-rotation ramps in from zero after a
    /// solve — so the circle doesn't snap on at full strength.
    private static let autoTiltRampInSec: Double = 3.0
    /// Seconds per full revolution of the auto-rotation circle.
    private static let autoTiltPeriodSec: Double = 14.0

    /// Resolve the (x-axis, y-axis) rotation for the current frame.
    /// Post-solve the puzzle drifts in a slow circle that ramps in
    /// over a few seconds. Pre-solve = no rotation at all; the player
    /// can no longer push the board to extreme angles via drag.
    private func rotationAngles(now: Date) -> (x: Double, y: Double) {
        guard game.solved, let start = game.solvedAt else {
            return (0, 0)
        }
        let elapsed = now.timeIntervalSince(start)
        let rampIn = min(1.0, elapsed / Self.autoTiltRampInSec)
        let phase = (elapsed / Self.autoTiltPeriodSec) * (.pi * 2)
        let ampX = Self.autoTiltMaxDegX * rampIn
        let ampY = Self.autoTiltMaxDegY * rampIn
        // Circle: x = sin, y = cos — gives a full rotation across
        // the XY tilt space every `autoTiltPeriodSec` seconds.
        return (ampX * sin(phase), ampY * cos(phase))
    }

    /// Render the solved-grid snapshot and save it to the Photos
    /// library. Requests add-only authorization on first use; the
    /// button icon flashes a ✓ on success or ✗ on denial/failure,
    /// then reverts to the neutral arrow after ~1.5 s.
    private func saveSolvedImage(puzzle: Puzzle) {
        guard let image = SolvedShareImage.render(puzzle: puzzle) else {
            flashSaveIcon(success: false)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Task { @MainActor in
                guard status == .authorized || status == .limited else {
                    flashSaveIcon(success: false)
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.creationRequestForAsset(from: image)
                } completionHandler: { ok, _ in
                    Task { @MainActor in
                        flashSaveIcon(success: ok)
                        if ok {
                            GameCenter.shared.reportAchievement(
                                GameCenter.Achievement.savedImage
                            )
                        }
                    }
                }
            }
        }
    }

    private func flashSaveIcon(success: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            saveImageIconName = success ? "checkmark.circle.fill" : "xmark.circle"
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                saveImageIconName = "square.and.arrow.down"
            }
        }
    }

    /// Main gameplay view — top bar, rotating grid, and the bank.
    /// Extracted so the loading ⇄ playing branch at the top of
    /// `body` can mount/unmount it inside a crossfade-animated
    /// Group. Keying this on `puzzle?.level` in the caller gives a
    /// smooth fade between levels instead of the old snap when
    /// `handleNext` reloads.
    /// Heights of the top / bottom window-background gradient strips.
    /// Doubles as layout padding for the grid so the un-zoomed puzzle
    /// lives in the lit middle region rather than disappearing under
    /// the UI chrome.
    private static let topBarStripHeight: CGFloat = 110
    private static let bottomBarStripHeight: CGFloat = 230

    @ViewBuilder
    private var playingContent: some View {
        // Layer order (back → front):
        //   1. Grid — full-screen so zoom overflow reaches the edges
        //   2. Top & bottom window-background gradients — fade to
        //      black where the UI sits so a zoomed grid visually
        //      darkens as it slides under the TopBar / Bank regions
        //   3. UI chrome (TopBar, optional BankView)
        // The solved-overlay row stays at the outer ContentView ZStack
        // level so it continues to sit above everything here.
        ZStack {
            // Only run the per-frame rotation path while solved —
            // that's the only time any angle is non-zero (player tilt
            // was removed; pre-solve angles are always (0,0)). During
            // active play a plain GridView is much cheaper: no 60fps
            // TimelineView diff, no 3D perspective compositing layer.
            Group {
                if game.solved {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        let angles = rotationAngles(now: timeline.date)
                        GridView(game: game)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 22)
                            .padding(.top, Self.topBarStripHeight)
                            .padding(.bottom, Self.bottomBarStripHeight)
                            .rotation3DEffect(
                                .degrees(angles.x),
                                axis: (x: 1, y: 0, z: 0),
                                perspective: 1.1
                            )
                            .rotation3DEffect(
                                .degrees(angles.y),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 1.1
                            )
                    }
                } else {
                    GridView(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 22)
                        .padding(.top, Self.topBarStripHeight)
                        .padding(.bottom, Self.bottomBarStripHeight)
                }
            }
            .scaleEffect(solveSquishScale)
            .animation(.spring(response: 0.12, dampingFraction: 0.55),
                       value: solveSquishScale)

            // Window-background gradients: black at the screen edges,
            // transparent toward the middle. Any zoomed-grid slice
            // that slides past the UI boundary gets blended into
            // black rather than poking out over the top bar or bank.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.topBarStripHeight)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.bottomBarStripHeight)
            }
            .ignoresSafeArea(edges: [.top, .bottom])
            .allowsHitTesting(false)

            // UI chrome on top of the gradients.
            VStack(spacing: 0) {
                TopBarView(
                    game: game,
                    menuOpen: $menuOpen,
                    perfectHeartNS: perfectHeartNS,
                    perfectHeartStage: perfectHeartStage,
                    heartWaveTick: heartWaveTick
                )
                .padding(.horizontal, 22)
                Spacer(minLength: 0)
                if !game.solved {
                    BankView(game: game)
                        .padding(.horizontal, 22)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .bottom))))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Map a tutorial flag → tooltip body text.
    private func tooltipText(for flag: TutorialFlag) -> String {
        switch flag {
        case .firstLaunch: return Strings.TutorialTooltips.challenge
        case .zenIntro:    return Strings.TutorialTooltips.zen
        case .dailyIntro:  return Strings.TutorialTooltips.daily
        }
    }

    /// Position the tooltip per-mode so it lands in the whitespace
    /// around the grid. Challenge (firstLaunch) points at the bank
    /// swatches at the bottom — tooltip sits just above them so the
    /// arrow of attention lands on the colors the player is about
    /// to drag. Zen and daily point at the top-bar controls, so
    /// those tooltips sit just under the top bar.
    ///
    /// Reduce-motion players see the old flat `TutorialTooltip`;
    /// everyone else gets the balloon with sway + float-away + tap-
    /// pop physics via `TutorialBalloon`.
    @ViewBuilder
    private func tutorialTooltipLayer(for flag: TutorialFlag) -> some View {
        if game.reduceMotion {
            flatTutorialLayer(for: flag)
        } else {
            balloonTutorialLayer(for: flag)
        }
    }

    @ViewBuilder
    private func flatTutorialLayer(for flag: TutorialFlag) -> some View {
        let released = tutorialExit != .alive
        VStack(spacing: 0) {
            TutorialTooltip(text: tooltipText(for: flag))
                .frame(maxWidth: 340)
                .padding(.top, 78)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .opacity(released ? 0 : 1)
        .animation(.easeOut(duration: 0.25), value: released)
        .onChange(of: tutorialExit) { _, newVal in
            if newVal != .alive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    finishTutorialUnmount()
                }
            }
        }
    }

    @ViewBuilder
    private func balloonTutorialLayer(for flag: TutorialFlag) -> some View {
        // Balloon position is fixed the same way the flat tooltip was
        // (top-center under the top bar). Per-flag color tint reads as
        // "slight tint" over a dark backdrop. The connector string to
        // the level chip (zenIntro only) is drawn elsewhere at the
        // ZStack root so it can see anchors from both subtrees — see
        // `balloonStringOverlay`.
        // Slight pink tint across every tutorial balloon — reads as a
        // unified "tutorial-speak" color without drifting into
        // mode-coded palettes.
        let tint = Color(red: 1.00, green: 0.72, blue: 0.82)
        VStack(spacing: 0) {
            TutorialBalloon(
                text: tooltipText(for: flag),
                tint: tint,
                exit: tutorialExit,
                onFinished: { finishTutorialUnmount() },
                onTap: {
                    if tutorialExit == .alive {
                        // First tap — release: mark seen and let the
                        // balloon float up slowly. Still tappable for
                        // the second tap to pop.
                        if let f = tutorialFlag { TutorialStore.markSeen(f) }
                        tutorialExit = .floating
                        zenTutorialBaselineLevel = nil
                    } else if tutorialExit == .floating {
                        // Second tap — pop the floating balloon.
                        // Capture the balloon's LAST KNOWN center
                        // before state change so the particle burst
                        // has a reliable origin even if the anchor
                        // unmounts in the same render tick.
                        if let center = balloonCenterLive {
                            popBurstOriginCapture = center
                        }
                        tutorialExit = .popped
                        Haptics.pop()
                        GlassyAudio.shared.playPop()
                        popBurstTint = tint
                        popBurstTick &+= 1
                        GameCenter.shared.reportAchievement(
                            GameCenter.Achievement.poppedBalloon
                        )
                    }
                },
                onSwipe: { dx, dy in
                    // Swipe dismiss — mark seen + send the balloon
                    // gliding off along the swipe vector.
                    if let f = tutorialFlag { TutorialStore.markSeen(f) }
                    zenTutorialBaselineLevel = nil
                    tutorialExit = .swipedAway(dx: dx, dy: dy)
                },
                knotAnchorKey: "balloonKnot",
                cornerArrow: flag == .zenIntro
            )
            .padding(.top, 78)
            Spacer(minLength: 0)
        }
    }

    /// Overlay that renders a falling-confetti burst whenever the
    /// player pops a tutorial balloon. The origin is captured via
    /// `onChange(of: popBurstTick)` while the balloon is still mounted
    /// (anchor available), then stored in `popBurstOriginCapture` so
    /// the 2.2-second particle animation can finish even after the
    /// balloon unmounts (which clears the anchor after ~0.11s).
    @ViewBuilder
    private var popBurstOverlay: some View {
        Color.clear
            .overlayPreferenceValue(TutorialAnchorsKey.self) { anchors in
                GeometryReader { geo in
                    ZStack {
                        // Continuously mirror the balloon's resolved
                        // center into `balloonCenterLive` so the tap
                        // handler can capture it synchronously. The
                        // previous onChange(of: popBurstTick) approach
                        // raced the .popped unmount animation — by the
                        // time the tick observation fired, the
                        // balloon's anchor preference could already
                        // be stale, leaving the burst with nil origin
                        // and no particles. Reading it here every
                        // render cycle keeps `balloonCenterLive`
                        // fresh while the balloon is alive.
                        Color.clear
                            .onAppear {
                                if let a = anchors["balloonCenter"] {
                                    let r = geo[a]
                                    balloonCenterLive = CGPoint(x: r.midX, y: r.midY)
                                }
                            }
                            .onChange(of: anchors["balloonCenter"] != nil) { _, has in
                                if has, let a = anchors["balloonCenter"] {
                                    let r = geo[a]
                                    balloonCenterLive = CGPoint(x: r.midX, y: r.midY)
                                } else {
                                    balloonCenterLive = nil
                                }
                            }
                            .onChange(of: popBurstTick) { _, tick in
                                // Second-chance capture for bursts that
                                // fired without a pre-captured origin.
                                if tick > 0, popBurstOriginCapture == nil,
                                   let a = anchors["balloonCenter"] {
                                    let r = geo[a]
                                    popBurstOriginCapture = CGPoint(
                                        x: r.midX, y: r.midY
                                    )
                                }
                            }
                        if let origin = popBurstOriginCapture, popBurstTick > 0 {
                            BalloonPopParticles(
                                origin: origin,
                                tint: popBurstTint,
                                containerHeight: geo.size.height,
                                onFinished: {
                                    popBurstTick = 0
                                    popBurstOriginCapture = nil
                                }
                            )
                            .id(popBurstTick)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
    }

    /// Overlay drawn at the ZStack root so the connector string from
    /// the balloon's knot to the level chip can resolve both anchors.
    /// TopBarView and the tutorial layer are sibling subtrees — only a
    /// common ancestor sees preferences from both. Hidden unless the
    /// zenIntro balloon is live.
    @ViewBuilder
    private var balloonStringOverlay: some View {
        if tutorialFlag == .zenIntro, !game.reduceMotion {
            Color.clear
                .overlayPreferenceValue(TutorialAnchorsKey.self) { anchors in
                    GeometryReader { geo in
                        if let chipA = anchors["chip"],
                           let knotA = anchors["balloonKnot"] {
                            let chip = geo[chipA]
                            let knot = geo[knotA]
                            BalloonStringToTargetShape(
                                knot: CGPoint(x: knot.midX, y: knot.midY),
                                target: CGPoint(x: chip.maxX + 6, y: chip.midY)
                            )
                            .stroke(Color.white.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 2,
                                                       lineCap: .round,
                                                       lineJoin: .round))
                            .opacity(tutorialExit == .alive ? 1 : 0.0)
                            .animation(.easeOut(duration: 0.25),
                                       value: tutorialExit)
                        }
                    }
                }
                .allowsHitTesting(false)
                .zIndex(31)
        }
    }

    /// Show the appropriate first-time tutorial for the current
    /// mode, if any. Flag mapping:
    ///   challenge → firstLaunch (very first app open lands here)
    ///   zen       → zenIntro
    ///   daily     → dailyIntro
    private func maybeShowTutorialForCurrentMode() {
        let flag: TutorialFlag? = {
            switch game.mode {
            case .challenge: return .firstLaunch
            case .zen:       return .zenIntro
            case .daily:     return .dailyIntro
            }
        }()
        guard let flag else { return }
        if !TutorialStore.hasSeen(flag), tutorialFlag != flag {
            tutorialFlag = flag
            zenTutorialBaselineLevel = (flag == .zenIntro) ? game.level : nil
        }
    }

    /// Begin the dismissal choreography for the active tutorial —
    /// marks it seen and flips the balloon into `.released` so it
    /// floats up and away. The balloon calls back into
    /// `finishTutorialUnmount()` when its exit animation completes so
    /// the flag actually clears. No-op if nothing is active.
    private func releaseTutorial() {
        guard tutorialFlag != nil else { return }
        if tutorialExit == .alive {
            if let f = tutorialFlag { TutorialStore.markSeen(f) }
            tutorialExit = .released
        }
        // If already .floating (user tapped balloon first, then
        // clicked the target), leave it floating — it'll drift away
        // on its own.
    }

    /// Called by the tutorial view (balloon or flat) once its exit
    /// animation is done. Actually clears the flag + resets the exit
    /// state so a future mode switch can show the next tutorial.
    private func finishTutorialUnmount() {
        tutorialFlag = nil
        tutorialExit = .alive
        zenTutorialBaselineLevel = nil
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

private struct RunCompleteOverlay: View {
    let levelsCompleted: Int
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 22) {
                Text("run complete!")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                VStack(spacing: 4) {
                    Text("levels complete")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(levelsCompleted)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                Button(action: onExit) {
                    Text("back to menu \u{2192}")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(Color(red: 42 / 255, green: 157 / 255, blue: 78 / 255))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 42 / 255, green: 157 / 255, blue: 78 / 255).opacity(0.38),
                                radius: 20, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(32)
        }
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
