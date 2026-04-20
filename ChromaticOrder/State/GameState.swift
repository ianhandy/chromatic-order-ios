//  Central observable store. One class per app (@MainActor bound) holds
//  the current puzzle + UI state and handles all actions: tap, drag,
//  check, skip, reset. Mirrors the responsibilities of App.jsx in the
//  web version but split out from the views.

import Foundation
import SwiftUI
import UIKit

enum GameMode: String { case zen, challenge, daily }

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

    /// Level chosen for today's daily — 8 to 15 rotation driven by seed.
    static func level(from seed: UInt64) -> Int {
        8 + Int(seed >> 32) % 8
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

@MainActor
@Observable
final class GameState {
    // Saved across sessions
    var level: Int
    var mode: GameMode
    var checks: Int
    var score: Int
    /// Persisted zen progression. Live `level` tracks whichever mode
    /// is active; this variable is the zen-specific counterpart so
    /// switching into challenge (which always restarts at level 1)
    /// doesn't nuke the player's zen progress.
    var zenLevel: Int
    /// Highest zen level the player has ever reached. Drives the
    /// top bar's level-picker sheet — the player can jump back to
    /// any earlier level without losing their max-reached marker.
    var zenMaxLevel: Int
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
    /// Frame rate cap for the main-menu palette animation. 30 / 60
    /// / 120 — 120 only pays off on ProMotion displays and can feel
    /// laggy on older devices. 60 is the default; pick higher for
    /// ProMotion-smooth motion, lower to reduce CPU load.
    var menuFps: Int

    // Live puzzle
    var puzzle: Puzzle?
    var generating: Bool = true
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
    var solved: Bool = false

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
    /// The date key of the currently loaded daily puzzle. nil outside
    /// of daily mode. Used to detect "the day rolled over, refresh".
    var dailyDateKey: String?
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
    /// ghost. Scales with `renderedCellSize` so the swatch always
    /// clears the cell directly under the thumb (ghost sits one
    /// cell-height + small buffer above). Clamped to 50pt so very
    /// small cells still get a usable lift above the thumb tip.
    var ghostLift: CGFloat { max(50, renderedCellSize + 20) }

    /// Effective drop point for hit-testing. Matches the ghost's
    /// lifted position — "the swatch falls wherever it's rendered."
    /// A player drops the tile at whatever cell the visual ghost is
    /// hovering over, not where the finger is. Keeps visual and
    /// logical placement locked together now that the lift is large
    /// enough to be meaningful.
    func effectivePoint(_ raw: CGPoint) -> CGPoint {
        CGPoint(x: raw.x, y: raw.y - ghostLift)
    }

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
        self.zenMaxLevel = loaded.zenMaxLevel
        self.level = loaded.zenLevel
        self.mode = .zen
        self.checks = 0
        self.score = 0
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
        self.solvedGlowEnabled = a11y.solvedGlowEnabled
        self.musicEnabled = a11y.musicEnabled
        self.sfxEnabled = a11y.sfxEnabled
        self.hapticsEnabled = a11y.hapticsEnabled
        self.menuFps = a11y.menuFps
        GlassyAudio.musicEnabled = a11y.musicEnabled
        GlassyAudio.sfxEnabled = a11y.sfxEnabled
        Haptics.isEnabled = a11y.hapticsEnabled
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
        var solvedGlowEnabled: Bool
        var musicEnabled: Bool
        var sfxEnabled: Bool
        var hapticsEnabled: Bool
        var menuFps: Int

        static let defaults = AccessibilityBundle(
            contrastScale: 1.0,
            lClampMin: OK.lMin, lClampMax: OK.lMax,
            cClampMin: OK.cMin, cClampMax: OK.cMax,
            doubleTapInterval: 0.28,
            magnetismEnabled: true,
            edgeVignetteEnabled: true,
            menuBackdropEnabled: true,
            solvedGlowEnabled: true,
            musicEnabled: true,
            sfxEnabled: true,
            hapticsEnabled: true,
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
            solvedGlowEnabled: (dict["solvedGlowEnabled"] as? Bool) ?? true,
            musicEnabled: (dict["musicEnabled"] as? Bool) ?? true,
            sfxEnabled: (dict["sfxEnabled"] as? Bool) ?? true,
            hapticsEnabled: (dict["hapticsEnabled"] as? Bool) ?? true,
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
            "solvedGlowEnabled": solvedGlowEnabled,
            "musicEnabled": musicEnabled,
            "sfxEnabled": sfxEnabled,
            "hapticsEnabled": hapticsEnabled,
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
        solvedGlowEnabled = d.solvedGlowEnabled
        musicEnabled = d.musicEnabled
        sfxEnabled = d.sfxEnabled
        hapticsEnabled = d.hapticsEnabled
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

    private static func loadProgress() -> (zenLevel: Int, zenMaxLevel: Int) {
        let ud = UserDefaults.standard
        guard let data = ud.data(forKey: progressKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (1, 1) }
        let v = dict["version"] as? Int ?? 1
        if v >= 3 {
            let zl = max(1, (dict["zenLevel"] as? Int) ?? 1)
            let zm = max(zl, (dict["zenMaxLevel"] as? Int) ?? zl)
            return (zl, zm)
        }
        if v == 2 {
            // v2 had only zenLevel — use it as both current and max.
            let zl = max(1, (dict["zenLevel"] as? Int) ?? 1)
            return (zl, zl)
        }
        // v1 migration: if the last saved mode was zen, carry its
        // level forward; otherwise start fresh at 1.
        let lv = (dict["level"] as? Int) ?? 1
        let mdRaw = (dict["mode"] as? String) ?? "zen"
        let zl = mdRaw == "zen" ? max(1, lv) : 1
        return (zl, zl)
    }

    private static func loadReduceMotion() -> Bool {
        let ud = UserDefaults.standard
        if ud.object(forKey: motionKey) != nil {
            return ud.bool(forKey: motionKey)
        }
        return UIAccessibility.isReduceMotionEnabled
    }

    private func saveProgress() {
        // Keep `zenLevel` in sync whenever we persist from zen, and
        // ratchet the max-reached marker so jumping back to earlier
        // levels never lowers it.
        if mode == .zen {
            zenLevel = level
            zenMaxLevel = max(zenMaxLevel, level)
        }
        let dict: [String: Any] = [
            "version": 3,
            "zenLevel": zenLevel,
            "zenMaxLevel": zenMaxLevel,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: progressKey)
            CloudSync.push(progressKey)
        }
    }

    private func saveReduceMotion() {
        UserDefaults.standard.set(reduceMotion, forKey: motionKey)
    }

    // ─── lifecycle ──────────────────────────────────────────────────

    func startLevel(_ lv: Int) {
        generating = true
        solved = false
        selection = nil
        dragSource = nil
        dragLocation = nil
        dropTarget = nil
        activeColor = nil
        showIncorrect = false
        engagedThisLevel = false
        currentFavoriteURL = nil
        // Diagnostics reset — fresh puzzle = fresh timer + mistake count.
        puzzleStartTime = Date()
        mistakeCount = 0
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
        let dailySeed: UInt64? = mode == .daily
            ? Daily.seed(for: dailyDateKey ?? Daily.dateKey())
            : nil
        Task.detached(priority: .userInitiated) { [weak self] in
            var cfg = GenConfig()
            cfg.cbMode = activeCBMode
            cfg.rangeScale = activeContrast
            cfg.lClampMin = activeL.min
            cfg.lClampMax = activeL.max
            cfg.cClampMin = activeC.min
            cfg.cClampMax = activeC.max
            let puz: Puzzle
            if let seed = dailySeed {
                let rng = SeededRNGRef(seed: seed)
                puz = GenRNG.$current.withValue(rng) {
                    generatePuzzle(level: lv, config: cfg)
                }
            } else {
                puz = generatePuzzle(level: lv, config: cfg)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.puzzle = puz
                self.generating = false
            }
        }
        saveProgress()
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

#if DEBUG
    /// Dev-only cheat — clears every pre-filled lock on the current
    /// puzzle (so the board starts empty with every solution color in
    /// the bank) AND bumps `zenMaxLevel` so the level picker exposes
    /// every tier through Master. Wired to the 3-second long-press on
    /// the settings button. Not compiled into Release.
    func debugUnlockAllLocks() {
        // Level picker is gated on zenMaxLevel; lift it past the highest
        // tier so the dev can jump directly to Expert/Master puzzles.
        zenMaxLevel = max(zenMaxLevel, 20)
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
#endif

    func handleNext() {
        let justCompleted = level
        // Capture "clean solve" signal before we clear flags — a
        // puzzle counts as clean when the player made zero mistakes
        // AND didn't pop the "show incorrect" peek. The streak in
        // Stats rests on this same rule.
        let cleanSolve = mistakeCount == 0 && !showedIncorrect
        // Daily: one puzzle per day — submit the time/accuracy score
        // and reload the same seeded puzzle so retries are allowed but
        // the level never advances past today's assignment.
        if mode == .daily {
            let timeBonus = max(0, 300 - timeSpentSec)
            let mistakePenalty = mistakeCount * 50
            let peekPenalty = showedIncorrect ? 500 : 0
            let base = max(1, level) * max(1, puzzle?.difficulty ?? 1) * 10
            let dailyScore = max(1, base + timeBonus - mistakePenalty - peekPenalty)
            GameCenter.shared.submitDailyScore(dailyScore)
            StatsStore.recordSolve(
                mode: "daily", clean: cleanSolve,
                solveSeconds: timeSpentSec,
                cbMode: cbMode.rawValue,
                challengeScore: nil
            )
            showedIncorrect = false
            startLevel(level)
            return
        }
        // If the player used "show incorrect" this puzzle, solving
        // it doesn't advance them — they stay on the same level and
        // try again next round. No demotion, no UI copy mentioning
        // the rule; the button is just silently a "peek that costs
        // the next-level bump."
        let nextLv = showedIncorrect ? level : level + 1
        if mode == .challenge {
            if let p = puzzle {
                // Level × difficulty — rewards both climbing the
                // ladder and tackling harder puzzles within a tier.
                // Level 1 diff 1 = 1 pt; level 10 diff 10 = 100 pts.
                score += max(1, level) * max(1, p.difficulty)
            }
            if justCompleted % 3 == 0 { checks += 1 }
            // Push the updated total to Game Center. Only the best
            // score per player is retained server-side so we can
            // submit on every solve without needing a local
            // high-water mark.
            GameCenter.shared.submitChallengeScore(score)
        }
        StatsStore.recordSolve(
            mode: mode.rawValue, clean: cleanSolve,
            solveSeconds: timeSpentSec,
            cbMode: cbMode.rawValue,
            challengeScore: mode == .challenge ? score : nil
        )
        showedIncorrect = false
        level = nextLv
        startLevel(nextLv)
    }

    func handleSkip() {
        if engagedThisLevel { showedIncorrect = false }
        startLevel(level)
    }

    func handleCheck() {
        guard let p = puzzle, !solved, checks > 0 else { return }
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
            playSolveChord()
            Haptics.solve()
        } else {
            checks -= 1
            showIncorrect = true
            saveProgress()
        }
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
    /// fresh run (level 1, score 0, three checks); restores the
    /// persisted zen level when returning to zen.
    func enterMode(_ target: GameMode) {
        // Save zen progress before leaving zen so picking zen again
        // later lands on the highest level the player has reached.
        if mode == .zen {
            zenLevel = level
            saveProgress()
        }
        mode = target
        showIncorrect = false
        showedIncorrect = false
        switch target {
        case .zen:
            level = zenLevel
            score = 0
            checks = 0
            dailyDateKey = nil
        case .challenge:
            level = 1
            score = 0
            checks = 3
            dailyDateKey = nil
        case .daily:
            let key = Daily.dateKey()
            dailyDateKey = key
            level = Daily.level(from: Daily.seed(for: key))
            score = 0
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
    func loadCustomPuzzle(_ p: Puzzle, favoriteURL: URL? = nil) {
        if mode != .zen {
            mode = .zen
            level = zenLevel
            score = 0
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
        puzzle = p
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
        }
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: progressKey)
        level = 1
        zenLevel = 1
        zenMaxLevel = 1
        mode = .zen
        checks = 0
        score = 0
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
        let clamped = min(max(1, lv), zenMaxLevel)
        level = clamped
        zenLevel = clamped
        showIncorrect = false
        showedIncorrect = false
        saveProgress()
        startLevel(clamped)
    }

    // ─── auto-check (zen) ───────────────────────────────────────────

    func checkAutoSolve() {
        guard mode == .zen, !solved, !generating, let p = puzzle else { return }
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
                self.playSolveChord()
                Haptics.solve()
            }
        }
    }

    /// Stacks the placed colors (one per unique cell) into a pentatonic
    /// chord the audio engine plays when the puzzle is solved. Skips
    /// locked/anchor cells — the "reward" sound should reflect the
    /// colors the player actually placed, not the starter clues.
    private func playSolveChord() {
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
        GlassyAudio.shared.play(item.color, kind: .place)
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
        GlassyAudio.shared.play(color, kind: .place)
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
        GlassyAudio.shared.play(movedItem.color, kind: .place)
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
            GlassyAudio.shared.play(landed, kind: .place)
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
        if let moved { GlassyAudio.shared.play(moved, kind: .place) }
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
        GlassyAudio.shared.play(color, kind: .place)
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
        GlassyAudio.shared.play(item.color, kind: .pickup)
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
            GlassyAudio.shared.play(color, kind: .pickup)
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
        GlassyAudio.shared.play(source.color, kind: .pickup)
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

    /// Tier chip shown in the top bar. Derives from the puzzle's
    /// actual `difficulty` score (1–10) when a puzzle is loaded, so
    /// custom puzzles opened via a share link display their real
    /// difficulty instead of the tier the player's zen level implies.
    /// Falls back to level-derived tier when no puzzle is present yet
    /// (cold launch, between-level regeneration).
    var tier: LevelTierInfo {
        if let p = puzzle {
            let i = min(max(0, (p.difficulty - 1) / 2), Tiers.labels.count - 1)
            return LevelTierInfo(index: i, label: Tiers.labels[i], colorHex: Tiers.hexes[i])
        }
        return levelTier(level)
    }

    /// Seconds elapsed since the current puzzle was generated. Used by
    /// the feedback form to correlate rated difficulty with dwell time
    /// (longer dwell on a low-tier puzzle = the rating isn't spurious).
    var timeSpentSec: Int { max(0, Int(Date().timeIntervalSince(puzzleStartTime))) }
}
