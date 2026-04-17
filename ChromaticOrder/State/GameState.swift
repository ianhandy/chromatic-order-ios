//  Central observable store. One class per app (@MainActor bound) holds
//  the current puzzle + UI state and handles all actions: tap, drag,
//  check, skip, reset. Mirrors the responsibilities of App.jsx in the
//  web version but split out from the views.

import Foundation
import SwiftUI
import UIKit

enum GameMode: String { case zen, challenge }

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

@MainActor
@Observable
final class GameState {
    // Saved across sessions
    var level: Int
    var mode: GameMode
    var checks: Int
    var score: Int
    var reduceMotion: Bool
    /// Color-blindness mode the generator and scorer build under. Saved
    /// alongside reduce-motion so Reset Progress doesn't stomp it —
    /// it's an accessibility setting, not game state.
    var cbMode: CBMode

    // Live puzzle
    var puzzle: Puzzle?
    var generating: Bool = true

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

    // How far above the finger the drag ghost floats. Purely visual —
    // placement still uses the raw finger position via effectivePoint
    // below. That's the intuitive mapping: the cell you point at is
    // the cell the color lands in; the ghost just gets out of the
    // thumb's way so you can see what you're targeting.
    static let ghostLift: CGFloat = 64

    /// Effective drop point for hit-testing. Pass-through now — the
    /// finger's position IS the placement position. (An earlier pass
    /// used the ghost's lifted position for placement, which let the
    /// ghost visually drift from the cell it would actually land in.)
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
        // -32pt which pulled too aggressively across gaps.
        let catchInset: CGFloat = -12
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
        let (savedLevel, savedMode, savedChecks, savedScore) = Self.loadProgress()
        self.level = savedLevel
        self.mode = savedMode
        self.checks = savedChecks
        self.score = savedScore
        self.reduceMotion = Self.loadReduceMotion()
        self.cbMode = Self.loadCBMode()
        startLevel(level)
    }

    private static func loadCBMode() -> CBMode {
        let raw = UserDefaults.standard.string(forKey: cbModeKey) ?? ""
        return CBMode(rawValue: raw) ?? .none
    }

    private func saveCBMode() {
        UserDefaults.standard.set(cbMode.rawValue, forKey: cbModeKey)
    }

    /// Advance to the next CB mode (wraps). Called by the menu toggle.
    /// Regenerates the current puzzle so the step math runs under the
    /// new vision — the player sees puzzles tuned for their eyes.
    func cycleCBMode() {
        cbMode = cbMode.next()
        saveCBMode()
        startLevel(level)
    }

    // ─── persistence ────────────────────────────────────────────────

    private static func loadProgress() -> (Int, GameMode, Int, Int) {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: progressKey),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (dict["version"] as? Int) == 1 {
            let lv = (dict["level"] as? Int) ?? 1
            let mdRaw = (dict["mode"] as? String) ?? "zen"
            let md: GameMode = mdRaw == "challenge" ? .challenge : .zen
            let cks = (dict["checks"] as? Int) ?? 3
            let sc = (dict["score"] as? Int) ?? 0
            return (max(1, lv), md, max(0, cks), max(0, sc))
        }
        return (1, .zen, 3, 0)
    }

    private static func loadReduceMotion() -> Bool {
        let ud = UserDefaults.standard
        if ud.object(forKey: motionKey) != nil {
            return ud.bool(forKey: motionKey)
        }
        return UIAccessibility.isReduceMotionEnabled
    }

    private func saveProgress() {
        let dict: [String: Any] = [
            "version": 1,
            "level": level,
            "mode": mode.rawValue,
            "checks": checks,
            "score": score,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: progressKey)
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
        // Capture the current CB mode at dispatch time — the detached
        // task runs off the main actor and can't read properties.
        let activeCBMode = cbMode
        Task.detached(priority: .userInitiated) { [weak self] in
            var cfg = GenConfig()
            cfg.cbMode = activeCBMode
            let puz = generatePuzzle(level: lv, config: cfg)
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

    func handleNext() {
        let justCompleted = level
        let nextLv = showedIncorrect ? max(1, level - 1) : level + 1
        if mode == .challenge {
            if let p = puzzle {
                score += max(1, p.difficulty)
            }
            if justCompleted % 3 == 0 { checks += 1 }
        }
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
        saveReduceMotion()
    }

    func switchMode() {
        mode = (mode == .zen) ? .challenge : .zen
        if mode == .challenge { checks = 3 }
        showIncorrect = false
        showedIncorrect = false
        saveProgress()
    }

    /// Jump into a player-authored puzzle. Bypasses the generator and
    /// level progression — treated as a one-off "custom" session. We
    /// keep `level` and progress untouched so dismissing the custom
    /// puzzle returns the player to where they were.
    func loadCustomPuzzle(_ p: Puzzle) {
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
        puzzle = p
    }

    func resetProgress() {
        UserDefaults.standard.removeObject(forKey: progressKey)
        level = 1
        mode = .zen
        checks = 3
        score = 0
        showedIncorrect = false
        showIncorrect = false
        startLevel(1)
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
        if allGood { solved = true }
    }

    // ─── bank slot helpers ──────────────────────────────────────────

    private func newBankUid() -> Int { defer { nextBankUid += 1 }; return nextBankUid }

    private func firstEmptySlot(in p: inout Puzzle) -> Int? {
        p.bank.firstIndex(where: { $0 == nil })
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
        checkAutoSolve()
    }

    func moveSlotToSlot(_ from: Int, _ to: Int) {
        guard var p = puzzle, from != to,
              from >= 0, from < p.bank.count,
              to >= 0, to < p.bank.count else { return }
        guard p.bank[from] != nil else { return }
        let f = p.bank[from]
        let t = p.bank[to]
        p.bank[from] = t
        p.bank[to] = f
        puzzle = p
        engagedThisLevel = true
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
        p.board[to.r][to.c].placed = p.board[from.r][from.c].placed
        p.board[from.r][from.c].placed = nil
        puzzle = p
        engagedThisLevel = true
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
        _ = item
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
        if cell.placed != nil {
            selection = BoardSelection(kind: .cell(idx))
            activeColor = cell.placed
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

    var tier: LevelTierInfo { levelTier(level) }
}
