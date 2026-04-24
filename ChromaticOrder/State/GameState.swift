//  Central observable store. One class per app (@MainActor bound) holds
//  the current puzzle + UI state and handles all actions: tap, drag,
//  check, skip, reset. Mirrors the responsibilities of App.jsx in the
//  web version but split out from the views.

import Foundation
import SwiftUI
import UIKit

enum GameMode: String { case zen, challenge, daily }

/// Main-menu backdrop style. Player-selectable in the Options sheet.
enum MenuStyle: String, CaseIterable, Identifiable {
    /// Traveling palette strips (original). Semi-transparent horizontal
    /// and vertical rows of OKLCh swatches drifting across the screen
    /// at a few speeds.
    case paletteStrips
    /// Continuous dense grid of shifting OKLCh cells with axis "flares"
    /// (single-cell pulses traveling along a row or column) and
    /// tap-triggered "ripples" (same pulse radiating outward).
    case continuousGrid

    var id: String { rawValue }
    var label: String {
        switch self {
        case .paletteStrips:  return "Palette strips"
        case .continuousGrid: return "Color grid"
        }
    }
}

/// Today's daily puzzle seed derivation. Uses UTC day-start so all
/// players on the planet see the same puzzle at the same moment, not
/// offset by local timezone. SHA-free hash is plenty — we just need
/// a deterministic spread across dates.
enum Daily {
    /// YYYY-MM-DD string of the UTC date for `now`.
    static func dateKey(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = cal.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// 64-bit seed for the given date key. Deterministic across devices.
    static func seed(for key: String) -> UInt64 {
        var h: UInt64 = 0xCBF29CE484222325
        for b in key.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001B3
        }
        return h
    }

    /// Level chosen for today's daily. Day-of-week ramp matching the
    /// server's `/api/daily` curve: Mon→Sun 8..14. Keeps the client's
    /// local expectations aligned with what the server returns, so
    /// the UI's level chip is right even before the server fetch
    /// finishes (or when it fails).
    static func level(for key: String) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let date = fmt.date(from: key) ?? Date()
        let weekday = cal.component(.weekday, from: date) // 1=Sun .. 7=Sat
        //                     Su Mo Tu We Th Fr Sa
        let byWeekday = [0,   14, 8, 9, 10, 11, 12, 13]
        return byWeekday[weekday]
    }

    /// Back-compat overload — earlier call sites pass the seed; day-of-
    /// week curve doesn't depend on it. Kept so other call sites keep
    /// compiling.
    static func level(from seed: UInt64) -> Int { level(for: dateKey()) }

    /// Seconds until the next UTC midnight — i.e., when the next
    /// daily becomes available. Used by the menu to render a
    /// live countdown next to "today's puzzle (completed)".
    static func secondsUntilNext(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        // Tomorrow's midnight UTC.
        let tomorrow = cal.date(
            byAdding: .day, value: 1,
            to: cal.startOfDay(for: now)
        ) ?? now.addingTimeInterval(86400)
        return max(0, Int(tomorrow.timeIntervalSince(now)))
    }
}

struct CellIndex: Hashable { let r: Int; let c: Int }

// Drop targets include both board cells and bank slots now — players
// can drag swatches between slots or back to the toolbox, just like
// onto the grid.
enum DropTarget: Hashable {
    case cell(CellIndex)
    case slot(Int)
}

struct BoardSelection: Equatable {
    enum Kind: Equatable {
        case bank(Int)    // slot index in puzzle.bank
        case cell(CellIndex)
    }
    let kind: Kind
}

struct DragSource: Equatable {
    enum Kind: Equatable {
        case bank(Int)    // slot index in puzzle.bank
        case cell(CellIndex)
    }
    let kind: Kind
    let color: OKLCh
}

private let progressKey = "chromaticOrderProgress"
private let motionKey   = "chromaticOrderReduceMotion"
private let cbModeKey   = "chromaticOrderCBMode"
private let a11yKey     = "chromaticOrderAccessibility"
private let challengeRunKey = "chromaticOrderChallengeRun"

@MainActor
@Observable
final class GameState {
    // Saved across sessions
    var level: Int
    var mode: GameMode
    var checks: Int
    /// Number of puzzles solved in the current challenge run. Drives
    /// the deliberately slow challenge progression:
    /// `1 + challengeSolveCount / challengeSolvesPerLevel`. Reset to
    /// zero whenever the player enters challenge fresh from the
    /// main menu — challenge is never mid-run persisted.
    var challengeSolveCount: Int = 0
    /// Two solves per tier — a moderate brake so players feel each
    /// difficulty for a couple of puzzles before climbing, without
    /// feeling stuck on a tier.
    let challengeSolvesPerLevel: Int = 2
    /// Set true when the player burns their last heart in challenge
    /// mode. Drives the "run complete!" overlay and signals to the
    /// UI that the current challenge run is over.
    var runComplete: Bool = false
    /// True when a suspended challenge run is sitting on disk waiting
    /// to be resumed. The main menu reads this to decide whether
    /// tapping "challenge" should start fresh or prompt the player
    /// to resume. Kept in sync with disk by save/discard helpers.
    var hasSavedChallengeRun: Bool = false
    /// Running count of consecutive challenge solves where the
    /// player did not lose a heart. Reset on any heart loss and on
    /// fresh challenge entry. Every 3rd consecutive no-heart solve
    /// grants one bonus level skip and resets the counter.
    var consecutiveNoHeartSolves: Int = 0
    /// Running count of consecutive challenge perfect solves (no
    /// mistakes, no peeks, every placement first-try correct). Every
    /// 2nd consecutive grants a bonus level skip and resets.
    var consecutivePerfectSolves: Int = 0
    /// Accumulated streak-bonus levels that add on top of the normal
    /// challenge progression. Permanent for the duration of the
    /// current challenge run; reset on `enterMode(.challenge)` fresh.
    var challengeBonusLevels: Int = 0
    /// Set true whenever a heart is lost on the current level (via a
    /// failed check). Reset at `startLevel` so each level has its own
    /// flag. Drives the consecutive-no-heart streak counter.
    var heartLostThisLevel: Bool = false
    /// Set by the UI when the perfect-solve heart has already been
    /// added to `checks` during its landing animation (see the
    /// perfect-heart fly-in flow in ContentView). `handleNext` reads
    /// this and skips its own `checks += 1` so the bonus heart isn't
    /// awarded twice.
    var perfectHeartAlreadyAwarded: Bool = false
    /// Drag translation captured during the post-solve tilt gesture.
    /// Lives on GameState so both ContentView (which reads it to
    /// rotate the grid) and CellView (which reads it to position the
    /// permanent rotation-dependent shine on perfect-solved cells)
    /// see the same value.
    var solveTilt: CGSize = .zero
    /// Flipped true when the player taps the "show incorrect" row in
    /// the hamburger during a daily puzzle and it's about to turn
    /// on. ContentView renders a confirmation alert against this
    /// flag so the player is warned that enabling it will disable
    /// leaderboard submission for today. The alert flips the flag
    /// back to false on either button.
    var dailyShowAnswersConfirmPending: Bool = false
    /// Persisted zen progression. Live `level` tracks whichever mode
    /// is active; this variable is the zen-specific counterpart so
    /// switching into challenge (which always restarts at level 1)
    /// doesn't nuke the player's zen progress.
    var zenLevel: Int
    /// Highest level the player has ever reached in **challenge**
    /// mode. Drives the zen level-picker ceiling — zen is explicitly
    /// gated on challenge progression, so a player can only revisit
    /// zen levels they've already cleared in a challenge run. Zen
    /// solves never bump this value.
    var challengeMaxLevel: Int
    var reduceMotion: Bool
    /// Color-blindness mode the generator and scorer build under. Saved
    /// alongside reduce-motion so Reset Progress doesn't stomp it —
    /// it's an accessibility setting, not game state.
    var cbMode: CBMode
    /// Accessibility bundle — contrast (multiplier on step ranges) and
    /// L / c clamps (tighter than OK's default usable band). Persisted
    /// under its own key; Reset Progress leaves these alone.
    var contrastScale: Double
    var lClampMin: Double
    var lClampMax: Double
    var cClampMin: Double
    var cClampMax: Double
    /// Max seconds between two taps that still register as a double-
    /// tap zoom toggle. Lower = tighter (demands quicker successive
    /// taps); higher = more forgiving for slower fingers. Lives in
    /// the accessibility bundle so it roundtrips with the other
    /// assist settings.
    var doubleTapInterval: Double
    /// Snap-to-nearest-cell assist during drags. Off = direct-hit
    /// only (finger must land inside the cell rect). Some players
    /// prefer that for precision placement.
    var magnetismEnabled: Bool
    /// Edge vignette bloom when the player is holding a swatch. Off
    /// = flat background, no color halo.
    var edgeVignetteEnabled: Bool
    /// Wave-grid backdrop on the main menu. Off = pure black menu.
    var menuBackdropEnabled: Bool
    /// Which main-menu visual mode the player prefers. The default
    /// `paletteStrips` is the original traveling-palettes field;
    /// `continuousGrid` is a tight color grid with axis flares and
    /// tap-triggered ripples (see ContinuousGridMenuField).
    var menuStyle: MenuStyle
    /// Radial glow burst behind solved cells. Off = just the color,
    /// no finale flash.
    var solvedGlowEnabled: Bool
    /// Background-music loop (F# Ionian phrase) plays on both menu
    /// and in-game. Off = silent background.
    var musicEnabled: Bool {
        didSet {
            GlassyAudio.musicEnabled = musicEnabled
        }
    }
    /// In-game sound effects (swatch pickup / place clicks, solve
    /// chord, menu bloom). Independent of `musicEnabled` so players
    /// can silence the ambient music and still hear placement clicks
    /// or vice versa.
    var sfxEnabled: Bool {
        didSet {
            GlassyAudio.sfxEnabled = sfxEnabled
        }
    }
    /// Taptic Engine feedback for pickup / place / solve / shake.
    /// Decoupled from `reduceMotion` so players who don't want visual
    /// motion can still feel the taps, and vice versa.
    var hapticsEnabled: Bool {
        didSet {
            Haptics.isEnabled = hapticsEnabled
        }
    }
    /// Show the puzzle solve-timer in the top bar. Some players find
    /// the running timer pressurizing; turn off to play without it.
    /// Internal timer still runs for leaderboard submissions.
    var timerVisible: Bool
    /// Frame rate cap for the main-menu palette animation. 30 / 60
    /// / 120 — 120 only pays off on ProMotion displays and can feel
    /// laggy on older devices. 60 is the default; pick higher for
    /// ProMotion-smooth motion, lower to reduce CPU load.
    var menuFps: Int

    // Live puzzle
    var puzzle: Puzzle?
    /// Cached bounding box of active cells. Recomputed only when a
    /// new board layout is loaded (not on every swatch placement).
    private(set) var puzzleBoundsMinR = 0
    private(set) var puzzleBoundsMaxR = 0
    private(set) var puzzleBoundsMinC = 0
    private(set) var puzzleBoundsMaxC = 0
    var generating: Bool = true
    /// True when daily-mode fetch returned no row (server 404, or
    /// network/decode miss). UI renders an empty state instead of a
    /// board. Reset at the top of every `startLevel` so a retry /
    /// mode switch clears the flag.
    var dailyUnavailable: Bool = false
    /// True when the currently-loaded puzzle came from the Gallery
    /// sheet (either user-saved or a favorite). Drives the in-game
    /// hamburger's Home row to read 'Gallery' and route back to the
    /// Gallery sheet instead of the main menu, matching the expected
    /// "return to where I came from" behavior. Cleared whenever a
    /// generator puzzle takes over via `startLevel`.
    var cameFromGallery: Bool = false
    /// Set by the in-game "← Gallery" hamburger row. MenuView reads
    /// this on appear and auto-presents its Gallery sheet, then
    /// clears the flag. Avoids routing a signal through a separate
    /// environment object or AppStorage key for a one-shot hop.
    var openGalleryOnMenuAppear: Bool = false
    /// Set when the current puzzle has been favorited (or loaded
    /// from favorites). nil otherwise. Drives the top-bar star's
    /// filled-vs-outline state and lets `toggleFavorite()` know
    /// which file to remove on un-favorite. Cleared on every
    /// `startLevel` so a new generated puzzle starts unfavorited.
    var currentFavoriteURL: URL?

    // Interaction
    var selection: BoardSelection?
    var dragSource: DragSource?
    var dragLocation: CGPoint?
    var dropTarget: DropTarget?
    var activeColor: OKLCh?
    var solved: Bool = false {
        didSet {
            // Capture the solve instant so `timeSpentSec` freezes at
            // the exact solve time and the top-bar timer stops
            // advancing. Cleared whenever the player leaves solved
            // state (new puzzle, handleReset, etc.).
            if solved && !oldValue {
                solvedAt = Date()
            } else if !solved {
                solvedAt = nil
            }
        }
    }
    /// Timestamp of the `solved` flag's most recent true-flip. Drives
    /// the frozen-timer behavior on the solved overlay.
    private(set) var solvedAt: Date? = nil

    // Zen-mode penalty: set when the player uses Show Incorrect; on the
    // next solve advance, drop one level instead of gaining one.
    var showIncorrect: Bool = false
    var showedIncorrect: Bool = false
    var engagedThisLevel: Bool = false

    // Frame maps, populated by the views via PreferenceKeys.
    var cellFrames: [CellIndex: CGRect] = [:]
    var bankSlotFrames: [Int: CGRect] = [:]

    // Zoom + pan state.
    //   zoomScale = 1.0 is the default/fit-to-screen view; cannot zoom
    //   further OUT than that (no empty space around the grid).
    //   >1.0 scales the grid up. GridView clamps the upper bound to
    //   whatever makes 3 cells span the short viewport axis — the max
    //   "zoom into the grid" that's still useful for single-cell
    //   targeting.
    //   Pinch gesture updates zoomScale live; double-tap toggles
    //   between 1.0 and the max. Pan enabled whenever zoomScale > 1.
    var zoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero

    /// Convenience — "am I in any zoomed state" for call sites that
    /// just need to disable cell drags while zoomed.
    var zoomed: Bool { zoomScale > 1.0001 }

    // Diagnostics for the feedback form — reset each startLevel and
    // bumped by action callbacks as the player plays. All of these are
    // soft signals (small sample per report); the dev uses them to
    // correlate puzzle metrics with actual play experience.
    var puzzleStartTime: Date = Date()
    var mistakeCount: Int = 0
    /// Count of times a swatch landed on the BOARD (cell-targeted
    /// placements only). Bank rearrangements, returning a swatch to
    /// the bank, and bank shuffles don't increment. Displayed
    /// alongside the timer; submitted to leaderboards as a tiebreaker
    /// / efficiency metric.
    var moveCount: Int = 0
    /// The date key of the currently loaded daily puzzle. nil outside
    /// of daily mode. Used to detect "the day rolled over, refresh".
    var dailyDateKey: String?
    /// Date key of the last daily puzzle the player completed. Persists
    /// across sessions so the menu can gray out "today's puzzle" and
    /// append "(completed)" after a successful solve, and so re-entry
    /// auto-solves the board instead of allowing a replay.
    var dailyCompletedKey: String?

    /// True when the player has already solved today's daily.
    var isDailyCompletedToday: Bool {
        dailyCompletedKey == Daily.dateKey()
    }
    /// Did the player vote on the quick-feedback widget this puzzle?
    /// nil = hasn't voted, true = liked, false = disliked. One vote
    /// per puzzle (widget disables after submit). Reset on startLevel.
    var liked: Bool? = nil

    // How far above the finger the drag ghost floats. Purely visual —
    // placement still uses the raw finger position via effectivePoint
    // below. Was 64pt historically; that lifted the ghost so far up
    /// Rendered on-screen cell size (including any zoom factor).
    /// GridView reports this on every layout so the drag-ghost lift
    /// and hit-test offset scale with whatever the player currently
    /// sees — tiny cells on a dense Expert puzzle vs. pinched-in 3×
    /// zoom cells both need different offsets to keep the swatch
    /// above the thumb.
    var renderedCellSize: CGFloat = 40

    /// Vertical offset from the finger to the center of the drag
    /// ghost. Scales modestly with `renderedCellSize` so dense grids
    /// still clear the thumb, but upper-clamped so chunky cells on
    /// medium-size grids don't yank the swatch halfway across the
    /// screen (the prior 0.85× multiplier produced ~55pt lifts at
    /// cellPx≈64 which read as "the swatch is floating off" rather
    /// than "tucked just above the finger").
    var ghostLift: CGFloat {
        let scaled = renderedCellSize * 0.55
        return min(48, max(32, scaled))
    }

    /// Effective drop point for hit-testing. The finger's position IS
    /// the placement position — the ghost floats above purely as
    /// visual feedback so the player can see the color they're
    /// holding. With large cells on sparse puzzles a lifted hit-test
    /// felt like the swatch was "overshooting" when the thumb was
    /// clearly on the target; returning the raw thumb point keeps
    /// "aim with finger" as the touch-native interaction.
    func effectivePoint(_ raw: CGPoint) -> CGPoint { raw }

    func hitTest(_ point: CGPoint) -> DropTarget? {
        // Bank slots first — they're bigger drop targets and the player
        // expects "drag near a slot, drop in slot."
        for (idx, rect) in bankSlotFrames {
            if rect.insetBy(dx: -12, dy: -12).contains(point) {
                return .slot(idx)
            }
        }
        guard let puzzle else { return nil }
        // Direct-hit cell
        for (idx, rect) in cellFrames where rect.contains(point) {
            let cell = puzzle.board[idx.r][idx.c]
            guard cell.kind == .cell, !cell.locked else { continue }
            return .cell(idx)
        }
        // Magnetism: only snap when the finger is inside a cell's
        // inflated rect. Kept small so the magnet grabs a cell when
        // the finger is genuinely near it, and lets go once the
        // finger moves into a gap — dialled back from the earlier
        // -32pt which pulled too aggressively across gaps. When the
        // player has disabled magnetism in Accessibility, drop the
        // inflation to 0 so only direct-hit cells accept drops.
        let catchInset: CGFloat = magnetismEnabled ? -12 : 0
        var bestIdx: CellIndex? = nil
        var bestDist = CGFloat.infinity
        for (idx, rect) in cellFrames {
            let cell = puzzle.board[idx.r][idx.c]
            guard cell.kind == .cell, !cell.locked else { continue }
            let catchRect = rect.insetBy(dx: catchInset, dy: catchInset)
            guard catchRect.contains(point) else { continue }
            let dx = rect.midX - point.x
            let dy = rect.midY - point.y
            let d2 = dx * dx + dy * dy
            if d2 < bestDist {
                bestDist = d2
                bestIdx = idx
            }
        }
        return bestIdx.map { .cell($0) }
    }

    private var nextBankUid: Int = 1_000_000

    init() {
        // Only zen progress persists — challenge is a fresh session
        // every time the player enters it (see `enterMode`).
        let loaded = Self.loadProgress()
        self.zenLevel = loaded.zenLevel
        self.challengeMaxLevel = loaded.challengeMaxLevel
        self.dailyCompletedKey = loaded.dailyCompletedKey
        self.hasSavedChallengeRun = Self.loadSavedChallengeRun() != nil
        self.level = loaded.zenLevel
        self.mode = .zen
        self.checks = 0
        let rm = Self.loadReduceMotion()
        self.reduceMotion = rm
        self.cbMode = Self.loadCBMode()
        let a11y = Self.loadAccessibility()
        self.contrastScale = a11y.contrastScale
        self.lClampMin = a11y.lClampMin
        self.lClampMax = a11y.lClampMax
        self.cClampMin = a11y.cClampMin
        self.cClampMax = a11y.cClampMax
        self.doubleTapInterval = a11y.doubleTapInterval
        self.magnetismEnabled = a11y.magnetismEnabled
        self.edgeVignetteEnabled = a11y.edgeVignetteEnabled
        self.menuBackdropEnabled = a11y.menuBackdropEnabled
        self.menuStyle = a11y.menuStyle
        self.solvedGlowEnabled = a11y.solvedGlowEnabled
        self.musicEnabled = a11y.musicEnabled
        self.sfxEnabled = a11y.sfxEnabled
        self.hapticsEnabled = a11y.hapticsEnabled
        self.timerVisible = a11y.timerVisible
        self.menuFps = a11y.menuFps
        // Audio + haptic flag sync is deferred to
        // ChromaticOrderApp.onAppear — setting GlassyAudio.musicEnabled
        // here triggers engine.start() before the audio converter
        // service is ready on physical devices (-302), producing a
        // black screen and crackling audio.
        startLevel(level)
    }

    // ─── Accessibility ──────────────────────────────────────────────

    private struct AccessibilityBundle {
        var contrastScale: Double
        var lClampMin: Double
        var lClampMax: Double
        var cClampMin: Double
        var cClampMax: Double
        var doubleTapInterval: Double
        var magnetismEnabled: Bool
        var edgeVignetteEnabled: Bool
        var menuBackdropEnabled: Bool
        var menuStyle: MenuStyle
        var solvedGlowEnabled: Bool
        var musicEnabled: Bool
        var sfxEnabled: Bool
        var hapticsEnabled: Bool
        var timerVisible: Bool
        var menuFps: Int

        static let defaults = AccessibilityBundle(
            contrastScale: 1.0,
            lClampMin: OK.lMin, lClampMax: OK.lMax,
            cClampMin: OK.cMin, cClampMax: OK.cMax,
            doubleTapInterval: 0.28,
            magnetismEnabled: true,
            edgeVignetteEnabled: true,
            menuBackdropEnabled: true,
            menuStyle: .continuousGrid,
            solvedGlowEnabled: true,
            musicEnabled: true,
            sfxEnabled: true,
            hapticsEnabled: true,
            timerVisible: true,
            menuFps: 60
        )
    }

    private static func loadAccessibility() -> AccessibilityBundle {
        guard let data = UserDefaults.standard.data(forKey: a11yKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .defaults }
        let b = AccessibilityBundle(
            contrastScale: (dict["contrastScale"] as? Double) ?? 1.0,
            lClampMin: (dict["lClampMin"] as? Double) ?? OK.lMin,
            lClampMax: (dict["lClampMax"] as? Double) ?? OK.lMax,
            cClampMin: (dict["cClampMin"] as? Double) ?? OK.cMin,
            cClampMax: (dict["cClampMax"] as? Double) ?? OK.cMax,
            doubleTapInterval: (dict["doubleTapInterval"] as? Double) ?? 0.28,
            magnetismEnabled: (dict["magnetismEnabled"] as? Bool) ?? true,
            edgeVignetteEnabled: (dict["edgeVignetteEnabled"] as? Bool) ?? true,
            menuBackdropEnabled: (dict["menuBackdropEnabled"] as? Bool) ?? true,
            menuStyle: (dict["menuStyle"] as? String)
                .flatMap(MenuStyle.init(rawValue:)) ?? .continuousGrid,
            solvedGlowEnabled: (dict["solvedGlowEnabled"] as? Bool) ?? true,
            musicEnabled: (dict["musicEnabled"] as? Bool) ?? true,
            sfxEnabled: (dict["sfxEnabled"] as? Bool) ?? true,
            hapticsEnabled: (dict["hapticsEnabled"] as? Bool) ?? true,
            timerVisible: (dict["timerVisible"] as? Bool) ?? true,
            menuFps: (dict["menuFps"] as? Int) ?? 60
        )
        return b
    }

    private func saveAccessibility() {
        let dict: [String: Any] = [
            "contrastScale": contrastScale,
            "lClampMin": lClampMin,
            "lClampMax": lClampMax,
            "cClampMin": cClampMin,
            "cClampMax": cClampMax,
            "doubleTapInterval": doubleTapInterval,
            "magnetismEnabled": magnetismEnabled,
            "edgeVignetteEnabled": edgeVignetteEnabled,
            "menuBackdropEnabled": menuBackdropEnabled,
            "menuStyle": menuStyle.rawValue,
            "solvedGlowEnabled": solvedGlowEnabled,
            "musicEnabled": musicEnabled,
            "sfxEnabled": sfxEnabled,
            "hapticsEnabled": hapticsEnabled,
            "timerVisible": timerVisible,
            "menuFps": menuFps,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: a11yKey)
        }
    }

    /// Snapshot of the accessibility values at the current puzzle's
    /// generation time — used to tell whether the sheet's slider
    /// changes actually altered anything worth regenerating for.
    private var contrastAtGeneration: Double = 1.0
    private var lClampMinAtGeneration: Double = OK.lMin
    private var lClampMaxAtGeneration: Double = OK.lMax
    private var cClampMinAtGeneration: Double = OK.cMin
    private var cClampMaxAtGeneration: Double = OK.cMax

    /// Called when the Accessibility sheet closes. If any of the
    /// generator-affecting values moved since the current puzzle was
    /// built, regenerate — otherwise no-op so rapid re-opens of the
    /// sheet don't thrash the board.
    func applyAccessibilityIfChanged() {
        saveAccessibility()
        // cbMode lives in its own UserDefaults key; the picker binds
        // straight to $game.cbMode so we never hit cycleCBMode() from
        // the sheet path. Persist it here too or the player's choice
        // reverts on next launch.
        saveCBMode()
        let changed = contrastScale != contrastAtGeneration
            || lClampMin != lClampMinAtGeneration
            || lClampMax != lClampMaxAtGeneration
            || cClampMin != cClampMinAtGeneration
            || cClampMax != cClampMaxAtGeneration
            || cbMode != cbModeAtGeneration
        if changed {
            startLevel(level)
        }
    }

    /// Restore every accessibility setting to its default. Convenience
    /// for the sheet's "Reset" button.
    func resetAccessibility() {
        let d = AccessibilityBundle.defaults
        contrastScale = d.contrastScale
        lClampMin = d.lClampMin
        lClampMax = d.lClampMax
        cClampMin = d.cClampMin
        cClampMax = d.cClampMax
        doubleTapInterval = d.doubleTapInterval
        magnetismEnabled = d.magnetismEnabled
        edgeVignetteEnabled = d.edgeVignetteEnabled
        menuBackdropEnabled = d.menuBackdropEnabled
        menuStyle = d.menuStyle
        solvedGlowEnabled = d.solvedGlowEnabled
        musicEnabled = d.musicEnabled
        sfxEnabled = d.sfxEnabled
        hapticsEnabled = d.hapticsEnabled
        timerVisible = d.timerVisible
        menuFps = d.menuFps
        cbMode = .none
        saveAccessibility()
        saveCBMode()
    }

    private static func loadCBMode() -> CBMode {
        let raw = UserDefaults.standard.string(forKey: cbModeKey) ?? ""
        return CBMode(rawValue: raw) ?? .none
    }

    private func saveCBMode() {
        UserDefaults.standard.set(cbMode.rawValue, forKey: cbModeKey)
    }

    /// CB mode the current puzzle was generated under. Used to detect
    /// whether a regeneration is needed when the settings menu closes.
    /// Set in startLevel's detached task.
    var cbModeAtGeneration: CBMode = .none

    /// Advance to the next CB mode (wraps). Saves the new mode so
    /// it persists, but does NOT regenerate the current puzzle yet —
    /// the player may be cycling through several options to find the
    /// right one, and regenerating on every tap would be jarring.
    /// applyDeferredCBModeChange() is what actually kicks off the
    /// regeneration, and the menu calls it when it closes.
    func cycleCBMode() {
        cbMode = cbMode.next()
        saveCBMode()
    }

    /// Called when the settings menu closes. Kept for backward compat —
    /// `applyAccessibilityIfChanged` covers CB + clamps + contrast in
    /// one pass. Routes to it so the menu's onChange hook still works.
    func applyDeferredCBModeChange() {
        applyAccessibilityIfChanged()
    }

    /// Double-tap jumps between the default fit-view (1.0) and the
    /// player's max zoom. Caller passes the current maxZoom since
    /// GridView computes it from the container size.
    func toggleZoom(max: CGFloat) {
        if zoomScale > 1.0001 {
            zoomScale = 1.0
            panOffset = .zero
        } else {
            zoomScale = max
        }
    }

    /// Set zoom directly — used by the pinch gesture. `max` is the
    /// current maxZoom so we never allow zooming past "3 cells fill
    /// the screen." Clamped below at 1.0 (can't zoom out past
    /// fit-view; there's no purpose to empty space around the grid).
    func setZoom(_ value: CGFloat, max: CGFloat) {
        let clamped = min(max, Swift.max(1.0, value))
        zoomScale = clamped
        if clamped <= 1.0001 { panOffset = .zero }
    }

    /// Apply a pan delta while zoomed; no-op when not zoomed so the
    /// grid can't drift on its own.
    func pan(by delta: CGSize) {
        guard zoomed else { return }
        panOffset = CGSize(
            width: panOffset.width + delta.width,
            height: panOffset.height + delta.height
        )
    }

    // ─── persistence ────────────────────────────────────────────────

    private static func loadProgress() -> (zenLevel: Int, challengeMaxLevel: Int, dailyCompletedKey: String?) {
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: progressKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (1, 1, nil) }
        let v = dict["version"] as? Int ?? 1
        if v >= 4 {
            let zl = max(1, (dict["zenLevel"] as? Int) ?? 1)
            let cm = max(1, (dict["challengeMaxLevel"] as? Int) ?? 1)
            let dck = dict["dailyCompletedKey"] as? String
            return (zl, cm, dck)
        }
        if v == 3 {
            // v3 tracked zenMaxLevel — a zen-side high-water mark.
            // The new gating uses challenge progression instead, so
            // start challengeMaxLevel at 1 regardless of prior zen
            // reach. Keep zenLevel so returning to zen lands where
            // the player left off (clamped by enterMode).
            let zl = max(1, (dict["zenLevel"] as? Int) ?? 1)
            let dck = dict["dailyCompletedKey"] as? String
            return (zl, 1, dck)
        }
        if v == 2 {
            let zl = max(1, (dict["zenLevel"] as? Int) ?? 1)
            return (zl, 1, nil)
        }
        // v1 migration: if the last saved mode was zen, carry its
        // level forward; otherwise start fresh at 1.
        let lv = (dict["level"] as? Int) ?? 1
        let mdRaw = (dict["mode"] as? String) ?? "zen"
        let zl = mdRaw == "zen" ? max(1, lv) : 1
        return (zl, 1, nil)
    }

    // ─── Challenge-run persistence ─────────────────────────────

    /// Snapshot of the in-progress challenge run written to
    /// UserDefaults whenever challenge state mutates. Does NOT
    /// preserve the currently-visible puzzle's board/bank — the
    /// resume flow generates a fresh puzzle at the saved level.
    /// Only the RUN metadata survives: level, hearts, and the
    /// slow-advance solve counter.
    struct SavedChallengeRun {
        var level: Int
        var checks: Int
        var solveCount: Int
    }

    private func saveChallengeRun() {
        guard mode == .challenge, !runComplete else { return }
        let payload: [String: Any] = [
            "version": 1,
            "level": level,
            "checks": checks,
            "challengeSolveCount": challengeSolveCount,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        UserDefaults.standard.set(data, forKey: challengeRunKey)
        hasSavedChallengeRun = true
    }

    func discardSavedChallengeRun() {
        UserDefaults.standard.removeObject(forKey: challengeRunKey)
        hasSavedChallengeRun = false
    }

    static func loadSavedChallengeRun() -> SavedChallengeRun? {
        guard let data = UserDefaults.standard.data(forKey: challengeRunKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return SavedChallengeRun(
            level: max(1, (dict["level"] as? Int) ?? 1),
            checks: max(0, (dict["checks"] as? Int) ?? 3),
            solveCount: max(0, (dict["challengeSolveCount"] as? Int) ?? 0)
        )
    }

    /// Restore a previously-suspended challenge run. Loads metadata
    /// only — the specific puzzle the player was on isn't preserved
    /// (startLevel generates a new one at the run's level). Stats
    /// (hearts, slow-advance counter) are restored exactly so the
    /// run continues from where it stood.
    func resumeChallengeRun() {
        guard let run = Self.loadSavedChallengeRun() else { return }
        mode = .challenge
        level = run.level
        checks = run.checks
        challengeSolveCount = run.solveCount
        showIncorrect = false
        showedIncorrect = false
        runComplete = false
        solved = false
        dailyDateKey = nil
        startLevel(level)
    }

    // ─── Misc persistence ──────────────────────────────────────

    private static func loadReduceMotion() -> Bool {
        let ud = UserDefaults.standard
        if ud.object(forKey: motionKey) != nil {
            return ud.bool(forKey: motionKey)
        }
        return UIAccessibility.isReduceMotionEnabled
    }

    private func saveProgress() {
        // Keep `zenLevel` in sync whenever we persist from zen so
        // returning to zen lands where the player left off. The
        // zen-side "max reached" no longer gates anything — the
        // ceiling is `challengeMaxLevel`, which is ratcheted from
        // challenge solves only (see `handleNext`).
        if mode == .zen {
            zenLevel = level
        }
        var dict: [String: Any] = [
            "version": 4,
            "zenLevel": zenLevel,
            "challengeMaxLevel": challengeMaxLevel,
        ]
        if let dck = dailyCompletedKey { dict["dailyCompletedKey"] = dck }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: progressKey)
            CloudSync.push(progressKey)
        }
    }

    private func saveReduceMotion() {
        UserDefaults.standard.set(reduceMotion, forKey: motionKey)
    }

    /// Recompute and cache the bounding box of active cells in the
    /// current puzzle. Call this whenever a new board *layout* is
    /// loaded — not needed for swatch placement/movement since
    /// `.kind` never changes during play.
    func recomputePuzzleBounds() {
        guard let p = puzzle else { return }
        var mnR = p.gridH, mxR = 0, mnC = p.gridW, mxC = 0
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                if r < mnR { mnR = r }; if r > mxR { mxR = r }
                if c < mnC { mnC = c }; if c > mxC { mxC = c }
            }
        }
        if mnR > mxR { mnR = 0; mxR = 0 }
        if mnC > mxC { mnC = 0; mxC = 0 }
        puzzleBoundsMinR = mnR; puzzleBoundsMaxR = mxR
        puzzleBoundsMinC = mnC; puzzleBoundsMaxC = mxC
    }

    // ─── lifecycle ──────────────────────────────────────────────────

    func startLevel(_ lv: Int) {
        generating = true
        dailyUnavailable = false
        // Starting a level via the generator means we're no longer
        // in a gallery-custom-play context; clear the flag so the
        // next Home tap goes to the main menu instead of re-opening
        // Gallery.
        cameFromGallery = false
        // Clear the once-claim perfect-heart token so the next
        // perfect solve can award a fresh +1. Both handleNext and
        // the ContentView flight task gate on this flag so only
        // one path awards per solve.
        perfectHeartAlreadyAwarded = false
        solved = false
        selection = nil
        dragSource = nil
        dragLocation = nil
        dropTarget = nil
        activeColor = nil
        showIncorrect = false
        engagedThisLevel = false
        currentFavoriteURL = nil
        // Per-level heart-loss flag resets each level so the streak
        // counter evaluated at solve time only reflects what
        // happened on THIS puzzle.
        heartLostThisLevel = false
        solveTilt = .zero
        cellFrames = [:]
        bankSlotFrames = [:]
        // Diagnostics reset — fresh puzzle = fresh timer + mistake + move count.
        puzzleStartTime = Date()
        mistakeCount = 0
        moveCount = 0
        liked = nil
        // Capture state at dispatch time — the detached task runs off
        // the main actor and can't read properties. Snapshot everything
        // the generator needs so the call-through is self-contained.
        let activeCBMode = cbMode
        let activeContrast = contrastScale
        let activeL = (min: lClampMin, max: lClampMax)
        let activeC = (min: cClampMin, max: cClampMax)
        cbModeAtGeneration = activeCBMode
        contrastAtGeneration = activeContrast
        lClampMinAtGeneration = activeL.min
        lClampMaxAtGeneration = activeL.max
        cClampMinAtGeneration = activeC.min
        cClampMaxAtGeneration = activeC.max
        // Capture daily seed (if any) so the detached task can install
        // the TaskLocal RNG override — TaskLocal values do NOT propagate
        // across detached task boundaries, so we set it inside.
        // Tutorial seed trumps daily when a first-run tooltip is still
        // unseen for the current mode: the tooltip copy + on-screen
        // position were designed around the puzzle the fixed seed
        // produces, so we need that specific layout to show up the
        // first time — randomness here would sometimes land the
        // tooltip on top of the exact cells it's pointing at.
        let tutorialSeed: UInt64? = {
            let flag: TutorialFlag? = {
                switch mode {
                case .challenge: return .firstLaunch
                case .zen:       return .zenIntro
                case .daily:     return .dailyIntro
                }
            }()
            guard let flag, !TutorialStore.hasSeen(flag) else { return nil }
            return flag.puzzleSeed
        }()
        let dailySeed: UInt64? = mode == .daily
            ? Daily.seed(for: dailyDateKey ?? Daily.dateKey())
            : nil
        // Prefer the tutorial seed so first-run flow is deterministic;
        // daily's shared-seed behavior still holds for everyone who's
        // already seen the dailyIntro tooltip.
        let genSeed: UInt64? = tutorialSeed ?? dailySeed
        // Snapshot mode so the detached task can decide whether to
        // try the community pool. Daily is excluded — its seed must
        // yield the same puzzle for every player.
        let activeMode = mode
        Task.detached(priority: .userInitiated) { [weak self] in
            var cfg = GenConfig()
            cfg.cbMode = activeCBMode
            cfg.rangeScale = activeContrast
            cfg.lClampMin = activeL.min
            cfg.lClampMax = activeL.max
            cfg.cClampMin = activeC.min
            cfg.cClampMax = activeC.max
            // Community injection: for zen + challenge, roll a
            // 30% chance to pull a weighted-random liked puzzle at
            // this level from the server pool instead of generating
            // fresh. On 404 / network miss / decode failure, fall
            // through to the local generator so play never blocks.
            var puz: Puzzle? = nil
            // Skip the community pool entirely while a tutorial is
            // pending — the deterministic seed path below owns the
            // first-run board layout.
            if activeMode != .daily, tutorialSeed == nil,
               Double.random(in: 0..<1) < 0.30 {
                if let community = await LikedPuzzleStore.fetchCommunityRandom(level: lv),
                   let data = community.json.data(using: .utf8),
                   let doc = try? CreatorCodec.decode(data),
                   let built = CreatorCodec.rebuild(doc),
                   // Reject legacy community puzzles whose gradients
                   // are perceptually palindromic — those were liked
                   // before the generator rejected them locally, but
                   // they're just as ambiguous in anyone else's hands.
                   // On rejection, fall through to local generation so
                   // the player still gets a puzzle at this level.
                   !hasPalindromicGradient(built.gradients, mode: activeCBMode) {
                    // Reject community puzzles the player has already
                    // solved or that match a recently-shown layout.
                    let f = PuzzleShape.fingerprint(
                        of: built.gradients,
                        gridW: built.gridW, gridH: built.gridH)
                    if !SolvedPuzzleHistory.contains(f) {
                        puz = built
                    }
                }
            }
            // Daily mode fetches from the shared server so every
            // player plays the same puzzle for a given UTC date.
            // Skipped when a first-run tooltip still owns the board
            // layout (tutorialSeed != nil) — in that case the
            // deterministic tutorial seed path below still runs. When
            // the fetch misses (404 = no daily published, or any
            // network failure), daily mode surfaces an empty state
            // instead of silently diverging into local generation.
            var dailyLevelOverride: Int? = nil
            var dailyMissing = false
            if puz == nil, activeMode == .daily, tutorialSeed == nil {
                let key = Daily.dateKey()
                if let fetched = await DailyFetcher.fetch(for: key) {
                    puz = fetched.puzzle
                    dailyLevelOverride = fetched.level
                } else {
                    dailyMissing = true
                }
            }
            // Local generator only runs for non-daily modes. Daily
            // puzzles must come from the server so every player sees
            // the same board — no fallback.
            if puz == nil, !dailyMissing {
                // Dev-only routing through the targeted-difficulty
                // generator. Flip via:
                //   UserDefaults.standard.set(true,
                //       forKey: "kroma.dev.targetedGen")
                // See TargetedGenerate.swift + the `targeted-difficulty`
                // branch of the web repo for the band-tuning sampler.
                let useTargeted = UserDefaults.standard.bool(forKey: "kroma.dev.targetedGen")
                if let seed = genSeed {
                    let rng = SeededRNGRef(seed: seed)
                    puz = GenRNG.$current.withValue(rng) {
                        useTargeted
                            ? generateTargetedPuzzle(level: lv, config: cfg,
                                                     mode: activeCBMode)
                            : generatePuzzle(level: lv, config: cfg)
                    }
                } else {
                    puz = useTargeted
                        ? generateTargetedPuzzle(level: lv, config: cfg,
                                                 mode: activeCBMode)
                        : generatePuzzle(level: lv, config: cfg)
                }
            }
            let finalPuz = puz
            let finalDailyLevel = dailyLevelOverride
            let finalDailyMissing = dailyMissing
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.puzzle = finalPuz
                self.dailyUnavailable = finalDailyMissing
                if finalPuz != nil {
                    self.recomputePuzzleBounds()
                }
                self.generating = false
                // If the server returned a different level than the
                // client predicted (curve disagreement or server-side
                // override), sync the UI so the level chip matches
                // the puzzle the player is actually solving.
                if self.mode == .daily, let overrideLv = finalDailyLevel, overrideLv != self.level {
                    self.level = overrideLv
                }
                // If this is today's daily and the player has already
                // completed it, auto-fill every cell with its solution
                // and flip `solved` so they land back on the finished
                // board instead of a replayable empty grid.
                if self.mode == .daily,
                   let key = self.dailyDateKey,
                   self.dailyCompletedKey == key {
                    self.autoSolveForReview()
                }
            }
        }
        saveProgress()
    }

    /// Populate every free cell on the current puzzle with its
    /// solution color, clear the bank, and flip `solved` so the
    /// board renders in its completed state. Used after cold-launch
    /// re-entry into an already-completed daily — the player sees
    /// the finished layout without being able to replay.
    private func autoSolveForReview() {
        guard var p = puzzle else { return }
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                if let sol = p.board[r][c].solution {
                    p.board[r][c].placed = sol
                }
            }
        }
        p.bank = Array(repeating: nil, count: p.initialBankCount)
        puzzle = p
        solved = true
        showIncorrect = false
        selection = nil
        dragSource = nil
        dragLocation = nil
    }

    func handleReset() {
        guard var p = puzzle else { return }
        // Rebuild bank from the unlocked solution cells, clear placed
        // colors, keep slot count the same as the puzzle started.
        var freshBank: [BankItem?] = []
        var freshBoard = p.board
        var uid = 0
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell && !p.board[r][c].locked {
                freshBoard[r][c].placed = nil
                if let sol = p.board[r][c].solution {
                    freshBank.append(BankItem(id: uid, color: sol))
                    uid += 1
                }
            }
        }
        freshBank.shuffle()
        // Pad to initialBankCount with nil slots if the math differs
        // (shouldn't in practice — belt + suspenders).
        while freshBank.count < p.initialBankCount { freshBank.append(nil) }
        p.board = freshBoard
        p.bank = freshBank
        puzzle = p
        solved = false
        selection = nil
        activeColor = nil
        showIncorrect = false
    }

    /// Player-facing unlock — clears every pre-filled lock on the
    /// current puzzle (so the board starts empty with every solution
    /// color in the bank) AND bumps `challengeMaxLevel` so the zen
    /// level picker exposes every tier through Master. Wired to the
    /// 3-second long-press on the settings button.
    func debugUnlockAllLocks() {
        // Zen picker is gated on challengeMaxLevel; lift it past the
        // highest tier so the player can jump to Expert/Master.
        challengeMaxLevel = max(challengeMaxLevel, 20)
        saveProgress()
        guard var p = puzzle else { return }
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                p.board[r][c].locked = false
                p.board[r][c].placed = nil
            }
        }
        for gi in 0..<p.gradients.count {
            for k in 0..<p.gradients[gi].cells.count {
                p.gradients[gi].cells[k].locked = false
            }
        }
        // Bank now holds every distinct board-cell solution. Intersections
        // contribute one item (not one per covering gradient).
        var freshBank: [BankItem?] = []
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                guard let sol = p.board[r][c].solution else { continue }
                freshBank.append(BankItem(id: newBankUid(), color: sol))
            }
        }
        freshBank.shuffle()
        p.bank = freshBank
        p.initialBankCount = freshBank.count
        puzzle = p
        solved = false
        selection = nil
        activeColor = nil
        showIncorrect = false
    }

    func handleNext() {
        let justCompleted = level
        // Capture "clean solve" signal before we clear flags — a
        // puzzle counts as clean when the player made zero mistakes
        // AND didn't pop the "show incorrect" peek. The streak in
        // Stats rests on this same rule.
        let cleanSolve = mistakeCount == 0 && !showedIncorrect
        // Daily: one puzzle per day — submit the time + moves metrics
        // and reload the same seeded puzzle so retries are allowed but
        // the level never advances past today's assignment.
        if mode == .daily {
            // Using "Show incorrect" on the daily disqualifies the run
            // from leaderboard submission — the player gets to see the
            // puzzle solved, but their time / moves don't go on Game
            // Center. Stats are still recorded locally so the streak +
            // history stay accurate.
            if !showedIncorrect {
                // Raw time + moves to their own daily leaderboards.
                // Game Center keeps the player's best per recurrence
                // period, so today's re-solves only overwrite if they
                // beat the prior best run.
                GameCenter.shared.submitDailySolveMetrics(
                    timeSec: timeSpentSec,
                    moves: moveCount
                )
            }
            StatsStore.recordSolve(
                mode: "daily", clean: cleanSolve,
                solveSeconds: timeSpentSec,
                cbMode: cbMode.rawValue
            )
            if let p = puzzle {
                SolvedPuzzleHistory.push(
                    PuzzleShape.fingerprint(of: p.gradients,
                                            gridW: p.gridW, gridH: p.gridH))
            }
            // Mark today's daily completed + persist across sessions.
            // Do NOT regenerate — the player sees the final layout and
            // the menu grays out the option until the next daily rolls
            // over. Replay is explicitly disallowed by spec.
            dailyCompletedKey = Daily.dateKey()
            saveProgress()
            return
        }
        // If the player used "show incorrect" this puzzle, solving
        // it doesn't advance them — they stay on the same level and
        // try again next round. No demotion, no UI copy mentioning
        // the rule; the button is just silently a "peek that costs
        // the next-level bump."
        var nextLv: Int
        if mode == .zen {
            // Zen mode never auto-advances difficulty. The player
            // chooses their level via the level picker; solving a
            // puzzle just regenerates a fresh one at the same level
            // so they can dwell on a tier as long as they like.
            nextLv = level
        } else if showedIncorrect {
            nextLv = level
        } else if mode == .challenge {
            // Challenge progression is deliberately slow — one level
            // per few solves. Streak bonuses (see below) stack on
            // top to reward clean and perfect play with extra skips.
            challengeSolveCount += 1
            // Consecutive streaks evaluated at solve time. Each
            // triggers an additional level skip when its threshold
            // is hit, then resets so the player has to re-earn it.
            if heartLostThisLevel {
                consecutiveNoHeartSolves = 0
            } else {
                consecutiveNoHeartSolves += 1
                if consecutiveNoHeartSolves >= 3 {
                    challengeBonusLevels += 1
                    consecutiveNoHeartSolves = 0
                }
            }
            if isPerfectSolve {
                consecutivePerfectSolves += 1
                if consecutivePerfectSolves >= 2 {
                    challengeBonusLevels += 1
                    consecutivePerfectSolves = 0
                }
            } else {
                consecutivePerfectSolves = 0
            }
            nextLv = 1 + challengeSolveCount / challengeSolvesPerLevel
                + challengeBonusLevels
        } else {
            nextLv = level + 1
        }
        if mode == .zen {
            // Zen can never climb past what challenge has unlocked.
            nextLv = min(nextLv, max(1, challengeMaxLevel))
        }
        if mode == .challenge {
            // Ratchet the zen ceiling to whatever the player has now
            // unlocked in challenge. Zen's level picker reads this
            // directly, so advancing in challenge is the only way to
            // open higher zen levels.
            challengeMaxLevel = max(challengeMaxLevel, nextLv)
            // Claim-once token shared with the ContentView perfect-
            // heart flight task. Whichever path fires first awards
            // the +1 and flips the flag; the other is a no-op. The
            // flag is cleared at the top of `startLevel` so the next
            // perfect solve can claim again.
            if isPerfectSolve && !perfectHeartAlreadyAwarded {
                checks += 1
                perfectHeartAlreadyAwarded = true
            }
            _ = justCompleted
        }
        StatsStore.recordSolve(
            mode: mode.rawValue, clean: cleanSolve,
            solveSeconds: timeSpentSec,
            cbMode: cbMode.rawValue
        )
        if let p = puzzle {
            SolvedPuzzleHistory.push(
                PuzzleShape.fingerprint(of: p.gradients,
                                        gridW: p.gridW, gridH: p.gridH))
        }
        // Append a challenge-mode solve stat to the liked-puzzle
        // record if this puzzle is in the player's liked pool.
        // Captured BEFORE `level = nextLv` so `timeSpentSec` and
        // `moveCount` still reflect this level, and isPerfectSolve
        // is still valid (solved==true).
        if mode == .challenge, let p = puzzle,
           let json = try? CreatorCodec.encodePuzzle(p) {
            let wasPerfect = isPerfectSolve
            let t = timeSpentSec
            let mv = moveCount
            LikedPuzzleStore.recordChallengeSolve(
                puzzleJSON: json,
                timeSec: t,
                moveCount: mv,
                wasPerfect: wasPerfect
            )
        }
        showedIncorrect = false
        level = nextLv
        startLevel(nextLv)
        if mode == .challenge {
            // Persist after every challenge advance so the player
            // can come back later and resume exactly at this level
            // and heart count.
            saveChallengeRun()
        }
    }

    func handleSkip() {
        if engagedThisLevel { showedIncorrect = false }
        startLevel(level)
    }

    func handleCheck() {
        guard let p = puzzle, !solved else { return }
        // Daily skips the heart budget entirely — it's a one-shot
        // puzzle per day, and there's no "run" to end. Challenge
        // still requires a heart to burn.
        if mode == .challenge, checks <= 0 { return }
        let allGood = p.gradients.allSatisfy { g in
            g.cells.allSatisfy { spec in
                if let placed = p.board[spec.r][spec.c].placed {
                    return OK.equal(placed, spec.color)
                }
                return false
            }
        }
        if allGood {
            solved = true
            showIncorrect = false
            // Chord + haptic are deferred to ContentView so the
            // grid squish animation can sync to the next beat.
        } else if mode == .daily {
            // Daily wrong check: flash the per-cell red outlines for
            // a couple of seconds so the player can see what missed.
            // No heart cost, no solution reveal — they can keep
            // adjusting and check again.
            showIncorrect = true
            Haptics.placeWrong()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if !solved { showIncorrect = false }
            }
            saveProgress()
        } else {
            // Challenge wrong check: costs exactly one heart per
            // level and then reveals the solution — no second
            // attempts, no multi-heart drains. `showedIncorrect`
            // marks this puzzle as "peeked" so the next-level
            // advance holds the level steady rather than climbing.
            checks -= 1
            heartLostThisLevel = true
            showedIncorrect = true
            Haptics.placeWrong()
            revealSolution()
            solved = true
            if checks == 0 {
                // Burning the last heart ends the run. The
                // "run complete!" overlay picks this up and
                // bounces the player back to the main menu.
                runComplete = true
                discardSavedChallengeRun()
            } else {
                saveChallengeRun()
            }
            saveProgress()
        }
    }

    /// Fill every gradient cell's `placed` with its `solution` color
    /// and empty the bank so the solved-state overlay can render the
    /// completed board. Used when a wrong Check should show the
    /// player what the answer was instead of letting them keep
    /// guessing.
    private func revealSolution() {
        guard var p = puzzle else { return }
        for r in 0..<p.board.count {
            for c in 0..<p.board[r].count {
                if p.board[r][c].kind == .cell,
                   let sol = p.board[r][c].solution {
                    p.board[r][c].placed = sol
                }
            }
        }
        for i in 0..<p.bank.count { p.bank[i] = nil }
        puzzle = p
        showIncorrect = false
    }

    func toggleShowIncorrect() {
        let next = !showIncorrect
        showIncorrect = next
        if next { showedIncorrect = true }
    }

    func toggleReduceMotion() {
        reduceMotion.toggle()
        // Haptics is a separate `hapticsEnabled` setting now; don't
        // implicitly flip it when the motion toggle moves.
        saveReduceMotion()
    }

    func switchMode() {
        enterMode((mode == .zen) ? .challenge : .zen)
    }

    /// Entry point from the main menu. Always resets challenge to a
    /// fresh run (level 1, three checks); restores the
    /// persisted zen level when returning to zen. Re-entering daily
    /// on the same date preserves the running puzzle + timer +
    /// moves — tapping "today's puzzle" again shouldn't nuke the
    /// player's in-progress run.
    func enterMode(_ target: GameMode) {
        // Save zen progress before leaving zen so picking zen again
        // later lands on the highest level the player has reached.
        if mode == .zen {
            zenLevel = level
            saveProgress()
        }
        let wasDaily = mode == .daily
        mode = target
        switch target {
        case .zen:
            showIncorrect = false
            showedIncorrect = false
            // Zen cannot exceed the player's challenge ceiling — if
            // saved zenLevel sits above it (possible after a reset
            // or a migration from the old zen-side gate), drop back
            // to the top of what challenge has unlocked.
            level = min(max(1, zenLevel), max(1, challengeMaxLevel))
            zenLevel = level
            checks = 0
            dailyDateKey = nil
        case .challenge:
            showIncorrect = false
            showedIncorrect = false
            level = 1
            checks = 3
            challengeSolveCount = 0
            challengeBonusLevels = 0
            consecutiveNoHeartSolves = 0
            consecutivePerfectSolves = 0
            heartLostThisLevel = false
            runComplete = false
            dailyDateKey = nil
            // Entering challenge from scratch discards any
            // suspended run — the resume flow uses
            // `resumeChallengeRun()` instead of going through
            // enterMode, so reaching this branch means the player
            // explicitly wants a fresh start.
            discardSavedChallengeRun()
        case .daily:
            let key = Daily.dateKey()
            let sameSession = wasDaily && dailyDateKey == key && puzzle != nil
            if sameSession {
                // Preserve puzzle + timer + moves + showedIncorrect
                // state. No regeneration, no reset.
                saveProgress()
                return
            }
            showIncorrect = false
            showedIncorrect = false
            dailyDateKey = key
            level = Daily.level(for: key)
            checks = 0
        }
        saveProgress()
        startLevel(level)
    }

    /// Jump into a player-authored puzzle. Bypasses the generator and
    /// level progression — treated as a one-off "custom" session.
    /// Always plays in zen mode: challenge is reserved for the
    /// generator's level ladder (and its per-puzzle scoring doesn't
    /// make sense for a one-off), so entering a custom puzzle from
    /// challenge forces a switch back to zen first.
    func loadCustomPuzzle(_ p: Puzzle, favoriteURL: URL? = nil, fromGallery: Bool = false) {
        if mode != .zen {
            mode = .zen
            level = zenLevel
            checks = 0
            saveProgress()
        }
        generating = false
        solved = false
        selection = nil
        dragSource = nil
        dragLocation = nil
        dropTarget = nil
        activeColor = nil
        showIncorrect = false
        showedIncorrect = false
        engagedThisLevel = false
        currentFavoriteURL = favoriteURL
        // Signal the hamburger-menu Home row to read 'Gallery' and
        // route back to the Gallery sheet instead of the main menu.
        // Cleared automatically on any subsequent `startLevel` call
        // (the generator path owns the non-custom lifecycle).
        cameFromGallery = fromGallery
        puzzleStartTime = Date()
        mistakeCount = 0
        moveCount = 0
        puzzle = p
        recomputePuzzleBounds()
    }

    /// Toggle the current puzzle's favorite status. Saves a .kroma
    /// file to the favorites store on favorite; deletes the tracked
    /// file on un-favorite. No-op if there's no live puzzle.
    func toggleFavorite() {
        guard let p = puzzle else { return }
        if let url = currentFavoriteURL {
            FavoritesStore.deleteURL(url)
            currentFavoriteURL = nil
        } else {
            currentFavoriteURL = try? FavoritesStore.save(p)
            if currentFavoriteURL != nil {
                GameCenter.shared.reportAchievement(
                    GameCenter.Achievement.favoritedLevel
                )
            }
        }
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: progressKey)
        // Clear every first-run tutorial flag so a fresh install
        // feel — the challenge / zen / daily tooltips all fire
        // again the next time each mode is entered.
        TutorialStore.resetAll()
        // Drop any suspended challenge run too; entering challenge
        // after a reset should always start at level 1.
        discardSavedChallengeRun()
        level = 1
        zenLevel = 1
        challengeMaxLevel = 1
        mode = .zen
        checks = 0
        showedIncorrect = false
        showIncorrect = false
        startLevel(1)
    }

    /// Jump directly to an earlier zen level the player has already
    /// reached. No-op in challenge or out-of-range. Preserves the
    /// max-reached marker so returning to a higher level later
    /// won't fight with it.
    func jumpToLevel(_ lv: Int) {
        guard mode == .zen else { return }
        let clamped = min(max(1, lv), challengeMaxLevel)
        level = clamped
        zenLevel = clamped
        showIncorrect = false
        showedIncorrect = false
        saveProgress()
        startLevel(clamped)
    }

    // ─── auto-check (zen) ───────────────────────────────────────────

    func checkAutoSolve() {
        // Auto-solve runs in both zen and daily modes (challenge
        // requires an explicit Check tap). Daily gives the player no
        // hearts and no Check button, so without auto-solve the
        // puzzle would never flip to solved even when every cell is
        // correct.
        let autoSolveModes: [GameMode] = [.zen, .daily]
        guard autoSolveModes.contains(mode),
              !solved, !generating, let p = puzzle else { return }
        let allGood = p.gradients.allSatisfy { g in
            g.cells.allSatisfy { spec in
                if let placed = p.board[spec.r][spec.c].placed {
                    return OK.equal(placed, spec.color)
                }
                return false
            }
        }
        if allGood {
            // Defer the solve-state flip to the next tick so the
            // final placement renders first. Otherwise the newly-
            // placed cell's fill transitions in alongside the
            // bank-slide-out + grid-recenter spring and visibly
            // lags behind the already-placed cells.
            Task { @MainActor [weak self] in
                guard let self, !self.solved else { return }
                self.solved = true
                // Chord + haptic are deferred to ContentView so the
                // grid squish animation can sync to the next beat.
            }
        }
    }

    /// Stacks the placed colors (one per unique cell) into a pentatonic
    /// chord the audio engine plays when the puzzle is solved. Skips
    /// locked/anchor cells — the "reward" sound should reflect the
    /// colors the player actually placed, not the starter clues.
    func playSolveChord() {
        guard let p = puzzle else { return }
        var colors: [OKLCh] = []
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell {
                let cell = p.board[r][c]
                if cell.locked { continue }
                if let color = cell.placed { colors.append(color) }
            }
        }
        GlassyAudio.shared.playSolveChord(colors: colors)
    }

    // ─── bank slot helpers ──────────────────────────────────────────

    private func newBankUid() -> Int { defer { nextBankUid += 1 }; return nextBankUid }

    private func firstEmptySlot(in p: inout Puzzle) -> Int? {
        p.bank.firstIndex(where: { $0 == nil })
    }

    /// A cell just got a new placed color — was it the wrong one? If so,
    /// bump the mistake counter. Silent when the placement is correct
    /// or the cell has no solution / is empty. Called after every
    /// board mutation that puts a color into a cell (not when a color
    /// is returned to the bank).
    private func recordPlacementAt(_ r: Int, _ c: Int, from board: [[BoardCell]]) {
        guard board[r][c].kind == .cell, !board[r][c].locked else { return }
        guard let placed = board[r][c].placed,
              let solution = board[r][c].solution else { return }
        // Every piece-lands-on-board event counts toward moves. Bank
        // shuffles, bank→bank swaps, and cell→bank moves don't call
        // this function so they're automatically excluded.
        moveCount += 1
        if OK.equal(placed, solution) {
            Haptics.placeCorrect()
            // First-placement dismisses the onboarding hint forever —
            // the player figured out the drag, no more need for the tip.
            if !UserDefaults.standard.bool(forKey: "onboardingSeen_v1") {
                UserDefaults.standard.set(true, forKey: "onboardingSeen_v1")
            }
        } else {
            mistakeCount += 1
            Haptics.placeWrong()
        }
    }

    // ─── actions (grid ↔ bank, bank ↔ bank, cell ↔ cell) ───────────

    func placeSlotIntoCell(_ slot: Int, at r: Int, _ c: Int) {
        guard var p = puzzle,
              slot >= 0, slot < p.bank.count,
              let item = p.bank[slot] else { return }
        guard p.board[r][c].kind == .cell, !p.board[r][c].locked else { return }
        // If cell already has a color, swap it back into the bank slot.
        let displaced = p.board[r][c].placed
        p.board[r][c].placed = item.color
        if let d = displaced {
            p.bank[slot] = BankItem(id: newBankUid(), color: d)
        } else {
            p.bank[slot] = nil
        }
        puzzle = p
        engagedThisLevel = true
        GlassyAudio.shared.playPlaceChordTone(for: item.color)
        recordPlacementAt(r, c, from: p.board)
        checkAutoSolve()
    }

    func placeCellIntoSlot(_ from: CellIndex, slot: Int) {
        guard var p = puzzle,
              slot >= 0, slot < p.bank.count else { return }
        guard p.board[from.r][from.c].kind == .cell,
              !p.board[from.r][from.c].locked,
              let color = p.board[from.r][from.c].placed else { return }
        // If target slot is occupied, swap: its color flows to the cell.
        if let existing = p.bank[slot] {
            p.board[from.r][from.c].placed = existing.color
            p.bank[slot] = BankItem(id: newBankUid(), color: color)
        } else {
            p.board[from.r][from.c].placed = nil
            p.bank[slot] = BankItem(id: newBankUid(), color: color)
        }
        puzzle = p
        engagedThisLevel = true
        GlassyAudio.shared.playPlaceChordTone(for: color)
        // Only the `from` cell got a new color (or went empty); the
        // empty case is handled by the guard in recordPlacementAt.
        recordPlacementAt(from.r, from.c, from: p.board)
        checkAutoSolve()
    }

    func moveSlotToSlot(_ from: Int, _ to: Int) {
        guard var p = puzzle, from != to,
              from >= 0, from < p.bank.count,
              to >= 0, to < p.bank.count else { return }
        guard let movedItem = p.bank[from] else { return }
        let f = p.bank[from]
        let t = p.bank[to]
        p.bank[from] = t
        p.bank[to] = f
        puzzle = p
        engagedThisLevel = true
        GlassyAudio.shared.playPlaceChordTone(for: movedItem.color)
    }

    func swapCells(_ a: CellIndex, _ b: CellIndex) {
        guard var p = puzzle else { return }
        guard p.board[a.r][a.c].kind == .cell, p.board[b.r][b.c].kind == .cell else { return }
        guard !p.board[a.r][a.c].locked, !p.board[b.r][b.c].locked else { return }
        let tmp = p.board[a.r][a.c].placed
        p.board[a.r][a.c].placed = p.board[b.r][b.c].placed
        p.board[b.r][b.c].placed = tmp
        puzzle = p
        engagedThisLevel = true
        if let landed = p.board[b.r][b.c].placed {
            GlassyAudio.shared.playPlaceChordTone(for: landed)
        }
        // Both cells got new colors — each is a potential mistake.
        recordPlacementAt(a.r, a.c, from: p.board)
        recordPlacementAt(b.r, b.c, from: p.board)
        checkAutoSolve()
    }

    func moveCellToCell(_ from: CellIndex, _ to: CellIndex) {
        guard var p = puzzle else { return }
        guard p.board[from.r][from.c].kind == .cell, p.board[to.r][to.c].kind == .cell else { return }
        guard !p.board[from.r][from.c].locked, !p.board[to.r][to.c].locked else { return }
        guard p.board[from.r][from.c].placed != nil else { return }
        if p.board[to.r][to.c].placed != nil {
            swapCells(from, to); return
        }
        let moved = p.board[from.r][from.c].placed
        p.board[to.r][to.c].placed = moved
        p.board[from.r][from.c].placed = nil
        puzzle = p
        engagedThisLevel = true
        if let moved { GlassyAudio.shared.playPlaceChordTone(for: moved) }
        // `to` cell received the color; `from` went empty (no count).
        recordPlacementAt(to.r, to.c, from: p.board)
        checkAutoSolve()
    }

    // Drag-off-grid fallback — put the removed color into the first
    // empty slot (or the earliest, to keep the bank packed-ish).
    func cellToBank(_ at: CellIndex) {
        guard var p = puzzle,
              p.board[at.r][at.c].kind == .cell,
              !p.board[at.r][at.c].locked,
              let color = p.board[at.r][at.c].placed,
              let slot = firstEmptySlot(in: &p) else { return }
        p.board[at.r][at.c].placed = nil
        p.bank[slot] = BankItem(id: newBankUid(), color: color)
        puzzle = p
        engagedThisLevel = true
        GlassyAudio.shared.playPlaceChordTone(for: color)
    }

    // ─── tap handling ───────────────────────────────────────────────

    func tapSlot(_ slot: Int) {
        guard !solved, let p = puzzle, slot < p.bank.count else { return }

        // Already-selected-as-source case
        if let sel = selection {
            switch sel.kind {
            case .bank(let from):
                if from == slot { clearSelection(); return }
                moveSlotToSlot(from, slot)
                clearSelection(); return
            case .cell(let from):
                placeCellIntoSlot(from, slot: slot)
                clearSelection(); return
            }
        }

        // No selection — tapping an empty slot does nothing; tapping a
        // slot with a swatch selects it.
        guard let item = p.bank[slot] else { return }
        selection = BoardSelection(kind: .bank(slot))
        activeColor = item.color
        GlassyAudio.shared.playPickupChordTone(for: item.color)
        Haptics.pickup()
    }

    func tapCell(at r: Int, _ c: Int) {
        guard !solved, let p = puzzle else { return }
        let cell = p.board[r][c]
        guard cell.kind == .cell, !cell.locked else { return }
        let idx = CellIndex(r: r, c: c)

        if let sel = selection {
            switch sel.kind {
            case .bank(let slot):
                placeSlotIntoCell(slot, at: r, c)
                clearSelection(); return
            case .cell(let from):
                if from == idx { clearSelection(); return }
                moveCellToCell(from, idx)
                clearSelection(); return
            }
        }
        if let color = cell.placed {
            selection = BoardSelection(kind: .cell(idx))
            activeColor = color
            GlassyAudio.shared.playPickupChordTone(for: color)
            Haptics.pickup()
        }
    }

    func clearSelection() {
        selection = nil
        activeColor = nil
    }

    // ─── drag plumbing ──────────────────────────────────────────────

    func beginDrag(_ source: DragSource, at loc: CGPoint) {
        dragSource = source
        dragLocation = loc
        selection = nil
        activeColor = nil
        GlassyAudio.shared.playPickupChordTone(for: source.color)
        Haptics.pickup()
    }

    func updateDrag(to loc: CGPoint) {
        dragLocation = loc
        dropTarget = hitTest(effectivePoint(loc))
    }

    func endDrag(moved: Bool) {
        defer {
            dragSource = nil
            dragLocation = nil
            dropTarget = nil
        }
        guard let source = dragSource else { return }
        if let target = dropTarget {
            switch (source.kind, target) {
            case (.bank(let slot), .cell(let t)):
                placeSlotIntoCell(slot, at: t.r, t.c)
            case (.cell(let from), .cell(let t)):
                if from != t { moveCellToCell(from, t) }
            case (.bank(let from), .slot(let to)):
                if from != to { moveSlotToSlot(from, to) }
            case (.cell(let from), .slot(let to)):
                placeCellIntoSlot(from, slot: to)
            }
        } else if moved, case .cell(let from) = source.kind {
            cellToBank(from)
        }
    }

    // ─── derived ────────────────────────────────────────────────────

    var heldColor: OKLCh? { activeColor ?? dragSource?.color }

    /// True if at least one placed, non-locked cell disagrees with its
    /// solution under the current CB mode. Drives the show-incorrect
    /// red border on the grid — we only blink the border when there's
    /// actually something wrong to point at, so a clean board with
    /// show-incorrect enabled stays calm.
    var hasAnyWrongCell: Bool {
        guard let p = puzzle else { return false }
        for r in 0..<p.gridH {
            for c in 0..<p.gridW {
                let cell = p.board[r][c]
                guard cell.kind == .cell, !cell.locked,
                      let placed = cell.placed,
                      let sol = cell.solution else { continue }
                if !OK.equal(placed, sol, mode: cbMode) { return true }
            }
        }
        return false
    }

    /// Tier chip shown in the top bar. Derives from the LEVEL the
    /// puzzle was generated at, not its computed `difficulty` score.
    /// Two reasons: (a) the score is a noisy 1–10 proxy and landed
    /// puzzles an entire tier off what the player asked for
    /// (generating at an Easy level could show a Medium chip when
    /// step geometry happened to score high), and (b) with
    /// `levelMaxDifficulty` gating generator output, the level is
    /// already the authoritative tier signal. Custom / share-link /
    /// community puzzles all carry a `level` field, so this path
    /// works for them too.
    var tier: LevelTierInfo {
        if let p = puzzle {
            return levelTier(p.level)
        }
        return levelTier(level)
    }

    /// Seconds elapsed since the current puzzle was generated. Used by
    /// the feedback form to correlate rated difficulty with dwell time
    /// (longer dwell on a low-tier puzzle = the rating isn't spurious).
    var timeSpentSec: Int {
        let end = solvedAt ?? Date()
        return max(0, Int(end.timeIntervalSince(puzzleStartTime)))
    }

    /// A "perfect" solve — no mistakes, never peeked at the solution
    /// via Show Incorrect, AND the number of placements equals the
    /// number of free cells (i.e., every move landed a swatch in its
    /// correct slot on the first try; no swapping or relocating).
    /// Drives the extra color-bleed + shine effect on solve.
    var isPerfectSolve: Bool {
        guard solved, let p = puzzle else { return false }
        let totalFree = p.initialBankCount
        return mistakeCount == 0
            && !showedIncorrect
            && moveCount == totalFree
    }
}
