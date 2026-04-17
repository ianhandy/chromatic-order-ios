//  Central observable store. One class per app (@MainActor bound) holds
//  the current puzzle + UI state and handles all actions: tap, drag,
//  check, skip, reset. Mirrors the responsibilities of App.jsx in the
//  web version but split out from the views.

import Foundation
import SwiftUI

enum GameMode: String { case zen, challenge }

struct CellIndex: Hashable { let r: Int; let c: Int }

struct BoardSelection: Equatable {
    enum Kind: Equatable { case bank(Int), cell(CellIndex) }
    let kind: Kind
}

struct DragSource: Equatable {
    enum Kind: Equatable { case bank(Int), cell(CellIndex) }
    let kind: Kind
    let color: OKLCh
}

private let progressKey = "chromaticOrderProgress"
private let motionKey   = "chromaticOrderReduceMotion"

@MainActor
@Observable
final class GameState {
    // Saved across sessions
    var level: Int
    var mode: GameMode
    var checks: Int
    // Cumulative score in challenge mode. Awarded on solve-advance in
    // proportion to puzzle.difficulty (1-10) — harder levels pay more.
    // Not used in zen mode; kept across mode switches so the player
    // doesn't lose a run by toggling.
    var score: Int
    var reduceMotion: Bool

    // Live puzzle
    var puzzle: Puzzle?
    var generating: Bool = true

    // Interaction
    var selection: BoardSelection?
    var dragSource: DragSource?
    var dragLocation: CGPoint?
    var dropTarget: CellIndex?
    var activeColor: OKLCh?
    var solved: Bool = false

    // Zen-mode penalty: set when the player uses Show Incorrect; on the
    // next solve advance, drop one level instead of gaining one. Reset
    // on skip only if the player engaged with the current puzzle.
    var showIncorrect: Bool = false
    var showedIncorrect: Bool = false
    var engagedThisLevel: Bool = false

    // Fresh uids for bank items returned from the board.
    private var nextBankUid: Int = 1_000_000

    // Cell frames in global coords, updated by each CellView. Used to
    // hit-test drag positions across views (SwiftUI gestures don't hand
    // pointer events across view boundaries on their own).
    var cellFrames: [CellIndex: CGRect] = [:]

    // The drag ghost floats this many points above the finger. Placement
    // uses the ghost's position too (finger → ghost is a fixed offset),
    // so the cell the player *sees* getting tinted is the one they drop
    // into. Shared between the ghost rendering (ContentView) and the
    // hit-test here so the two can't drift out of sync.
    static let ghostLift: CGFloat = 48

    /// Effective drop point for hit-testing — the ghost's center,
    /// not the raw finger position.
    func effectivePoint(_ raw: CGPoint) -> CGPoint {
        CGPoint(x: raw.x, y: raw.y - Self.ghostLift)
    }

    func hitTest(_ point: CGPoint) -> CellIndex? {
        guard let puzzle else { return nil }
        // Direct hit first. Skip dead cells and locked cells so dragging
        // onto them never registers as a target.
        for (idx, rect) in cellFrames where rect.contains(point) {
            let cell = puzzle.board[idx.r][idx.c]
            guard cell.kind == .cell, !cell.locked else { continue }
            return idx
        }
        // Magnetism: only snap when the finger is inside a cell's
        // *inflated* rect — so the pull is local to each cell, not a
        // grid-wide Euclidean radius. The gaps between cells and the
        // dead-cell spaces stay non-magnetic, matching "color should
        // only be magnetized to cells, not just anywhere on the grid."
        let catchInset: CGFloat = -18  // expand rect by 18pt on every side
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
        return bestIdx
    }

    init() {
        let (savedLevel, savedMode, savedChecks, savedScore) = Self.loadProgress()
        self.level = savedLevel
        self.mode = savedMode
        self.checks = savedChecks
        self.score = savedScore
        self.reduceMotion = Self.loadReduceMotion()
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
            // Score added after v1 ship — absent on old saves, treat as 0.
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
        // `showedIncorrect` kept as caller-controlled (handleSkip /
        // handleNext own the lifecycle).
        Task.detached(priority: .userInitiated) { [weak self] in
            let puz = generatePuzzle(level: lv)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.puzzle = puz
                self.generating = false
            }
        }
        saveProgress()
    }

    func handleReset() {
        guard let p = puzzle else { return }
        // Rewind placements + bank back to the original puzzle state.
        var b = p.board
        var bank: [BankItem] = []
        var uid = 0
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where b[r][c].kind == .cell {
                if b[r][c].locked { continue }
                if let placed = b[r][c].placed {
                    bank.append(BankItem(id: uid, color: placed)); uid += 1
                    _ = placed
                }
                b[r][c].placed = nil
            }
        }
        puzzle?.board = b
        // Rebuild from the puzzle's original bank composition by
        // returning every non-locked cell's solution color instead.
        // Simpler: ask the generator result's original bank; since we
        // kept it on puzzle, reuse it (freshly shuffled).
        puzzle?.bank = p.bank
        for r in 0..<p.gridH {
            for c in 0..<p.gridW where p.board[r][c].kind == .cell && !p.board[r][c].locked {
                puzzle?.board[r][c].placed = nil
            }
        }
        solved = false
        selection = nil
        activeColor = nil
        showIncorrect = false
    }

    func handleNext() {
        let justCompleted = level
        let nextLv = showedIncorrect ? max(1, level - 1) : level + 1
        if mode == .challenge {
            // Points for challenge-mode solves only. Difficulty is
            // already 1-10 and roughly tracks effort, so it doubles as
            // a natural points scale.
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
            // Correct check is free — hearts budget the wrong guesses.
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

    // ─── actions ────────────────────────────────────────────────────

    private func newBankUid() -> Int { defer { nextBankUid += 1 }; return nextBankUid }

    func placeBankIntoCell(uid: Int, at r: Int, _ c: Int) {
        guard var p = puzzle else { return }
        guard let item = p.bank.first(where: { $0.id == uid }) else { return }
        guard p.board[r][c].kind == .cell, !p.board[r][c].locked else { return }
        p.bank.removeAll { $0.id == uid }
        if let displaced = p.board[r][c].placed {
            p.bank.append(BankItem(id: newBankUid(), color: displaced))
        }
        p.board[r][c].placed = item.color
        puzzle = p
        engagedThisLevel = true
        checkAutoSolve()
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

    func cellToBank(_ at: CellIndex) {
        guard var p = puzzle else { return }
        guard p.board[at.r][at.c].kind == .cell,
              !p.board[at.r][at.c].locked,
              let color = p.board[at.r][at.c].placed else { return }
        p.board[at.r][at.c].placed = nil
        p.bank.append(BankItem(id: newBankUid(), color: color))
        puzzle = p
        engagedThisLevel = true
    }

    // ─── tap / drag ──────────────────────────────────────────────────

    func tapBank(uid: Int) {
        guard !solved, let p = puzzle else { return }
        if case .bank(let existing) = selection?.kind, existing == uid {
            clearSelection(); return
        }
        guard let item = p.bank.first(where: { $0.id == uid }) else { return }
        selection = BoardSelection(kind: .bank(uid))
        activeColor = item.color
    }

    func tapCell(at r: Int, _ c: Int) {
        guard !solved, let p = puzzle else { return }
        let cell = p.board[r][c]
        guard cell.kind == .cell, !cell.locked else { return }
        let idx = CellIndex(r: r, c: c)

        if let sel = selection {
            switch sel.kind {
            case .bank(let uid):
                placeBankIntoCell(uid: uid, at: r, c)
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

    func beginDrag(_ source: DragSource, at loc: CGPoint) {
        dragSource = source
        dragLocation = loc
        selection = nil
        activeColor = nil
    }

    func updateDrag(to loc: CGPoint, target: CellIndex?) {
        dragLocation = loc
        dropTarget = target
    }

    /// Convenience: callers pass raw finger position; we apply the
    /// ghost lift internally so hit-tests and placement align with the
    /// visible tile, not the hidden fingertip.
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
        guard let source = dragSource, let p = puzzle else { return }
        if let t = dropTarget,
           p.board[t.r][t.c].kind == .cell,
           !p.board[t.r][t.c].locked {
            switch source.kind {
            case .bank(let uid):
                placeBankIntoCell(uid: uid, at: t.r, t.c)
            case .cell(let from):
                if from != t { moveCellToCell(from, t) }
            }
        } else if moved, case .cell(let from) = source.kind {
            // Dropped a cell drag outside any cell → back to bank.
            cellToBank(from)
        }
    }

    // ─── derived ────────────────────────────────────────────────────

    var heldColor: OKLCh? { activeColor ?? dragSource?.color }

    var tier: LevelTierInfo { levelTier(level) }
}
