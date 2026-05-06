//  Independent solver — counts the number of distinct bank-to-free-
//  cell placements that pass the game's `handleCheck` semantics, and
//  explains the structure of any ambiguity it finds.
//
//  This does NOT reuse the generator's uniqueness guards. It is a
//  ground-truth verifier: treat the finalized Puzzle as opaque input,
//  enumerate every way the bank could land on free cells, and count
//  the ones that would make the runtime's `OK.equal(placed, spec.color)`
//  pass on every cell.
//
//  Semantics mirror `GameState.handleCheck`:
//    allGood = every gradient's every spec satisfies
//              placed ≠ nil && OK.equal(placed!, spec.color, mode:)
//
//  "Distinct" placements are compared by their resulting per-cell
//  colors (as a (r,c) -> OKLCh map), not by bank-item identity — if
//  two bank items share a color under ΔE 2, swapping them produces
//  the same visible placement and does not count twice.

import Foundation

/// Describes WHY a puzzle has more than one visible valid placement.
/// Returned by `PuzzleSolver.diagnose`; nil when the puzzle is unique.
struct AmbiguityReport {

    /// One cell whose color differs between the canonical placement
    /// (bank item targeted at this cell) and an alternate valid
    /// placement the solver found. `canonical` and `alternate` are the
    /// actual bank-item colors placed at this cell under each scheme;
    /// `solution` is the spec's expected color.
    struct CellDiff: CustomStringConvertible {
        let r: Int
        let c: Int
        let canonical: OKLCh
        let alternate: OKLCh
        let solution: OKLCh

        var description: String {
            func f(_ c: OKLCh) -> String {
                String(format: "(L=%.3f,c=%.3f,h=%.1f)", c.L, c.c, c.h)
            }
            return "(\(r),\(c)) canon=\(f(canonical)) alt=\(f(alternate)) sol=\(f(solution))"
        }
    }

    /// Best-guess root cause of the ambiguity. Heuristic — the solver
    /// finds the first alternate placement via backtracking and labels
    /// based on its structure. Doesn't try to enumerate every possible
    /// category; `.bankCrossMatch` is the catch-all.
    enum Kind: String {
        /// Every differing cell lies on a single gradient AND the
        /// alternate colors at those cells are a pairwise swap of the
        /// canonical colors (alternate[i] ≈ canonical[n-1-i] etc). The
        /// gradient is perceptually palindromic — guard 3.5 in
        /// `Generate.swift` should have rejected this puzzle. Seeing
        /// this means guard 3.5 has a bug or was bypassed.
        case palindromicGradient

        /// The differing cells are on one gradient but NOT a full
        /// reversal — some suffix, prefix, or pair-swap. Happens when
        /// a partial reversal of the gradient's color sequence still
        /// satisfies every lock and intersection. Normally killed by
        /// guard 4's orientation-mask enumerator.
        case partialGradientReversal

        /// Differing cells span multiple gradients OR involve bank
        /// items whose color differs from the cell's spec.color. Means
        /// the bank contains colors that cross-match multiple cells —
        /// generator-side bank-build bug, or a ΔE-threshold edge case.
        case bankCrossMatch

        /// Couldn't classify. Shouldn't happen under the current
        /// generator — here so future weird cases don't silently fall
        /// through.
        case unknown
    }

    let kind: Kind
    let involvedGradientIds: [Int]
    let differingCells: [CellDiff]
    /// Full canonical cell -> color map, for log reproduction.
    let canonicalPlacement: [(r: Int, c: Int, color: OKLCh)]
    /// Full alternate cell -> color map.
    let alternatePlacement: [(r: Int, c: Int, color: OKLCh)]

    /// One-line summary suitable for test-failure logs.
    var summary: String {
        let grads = involvedGradientIds.map(String.init).joined(separator: ",")
        return "kind=\(kind.rawValue) grads=[\(grads)] " +
               "differingCells=\(differingCells.count) " +
               "firstDiff=\(differingCells.first?.description ?? "-")"
    }
}

enum PuzzleSolver {

    /// Count distinct visible placements (up to `limit`). Thin wrapper
    /// around `findPlacements` that discards the matchings.
    ///
    /// `enforceStepConsistency` (Rule 2): when true (default), a
    /// placement is valid only if for every consecutive cell pair on
    /// every gradient, the delta between placed colors equals that
    /// gradient's step vector within ΔE 2. Canonical placements
    /// satisfy this by construction; alternate matchings that swap
    /// bank items across unrelated cells typically violate it. Turning
    /// the flag off reproduces the pre-Rule-2 semantics (per-cell
    /// OK.equal only).
    static func countValidPlacements(_ puzzle: Puzzle,
                                     mode: CBMode = .none,
                                     limit: Int = 2,
                                     enforceStepConsistency: Bool = true) -> Int {
        findPlacements(puzzle, mode: mode, limit: limit,
                       enforceStepConsistency: enforceStepConsistency).count
    }

    /// True iff the puzzle has exactly one visible valid placement
    /// (Rule 2 enforced).
    static func isUniquelySolvable(_ puzzle: Puzzle, mode: CBMode = .none) -> Bool {
        countValidPlacements(puzzle, mode: mode, limit: 2) == 1
    }

    /// Find the minimum set of locked cells that still leaves the
    /// puzzle uniquely solvable. Greedy: start with the generator's
    /// current lock set, try removing each lock, keep the removal iff
    /// uniqueness still holds. Reruns until no further lock can be
    /// removed.
    ///
    /// Greedy, not optimal — the true minimum is NP-hard (set cover
    /// relative). In practice, greedy arrives within 1–2 locks of
    /// the optimum for n ≤ 30 cells. Returns the (r,c) coordinates of
    /// the minimum-required lock set.
    ///
    /// Uses: difficulty scoring. "Your current puzzle shows X locks;
    /// the minimum needed is Y. (X − Y) locks are redundant hints."
    /// The closer X is to Y, the harder the puzzle.
    static func minimumLockSet(_ puzzle: Puzzle,
                               mode: CBMode = .none) -> [(r: Int, c: Int)] {
        // Bail if the puzzle isn't uniquely solvable to start —
        // removing locks won't make it MORE unique.
        guard isUniquelySolvable(puzzle, mode: mode) else { return [] }

        var current = puzzle
        // Sort lock candidates by (r, c) for deterministic output.
        var remainingLocks: [(r: Int, c: Int)] = []
        var seen: Set<Int> = []
        for g in current.gradients {
            for spec in g.cells where spec.locked {
                let key = spec.r * 64 + spec.c
                if seen.contains(key) { continue }
                seen.insert(key)
                remainingLocks.append((spec.r, spec.c))
            }
        }
        remainingLocks.sort { ($0.r, $0.c) < ($1.r, $1.c) }

        var changed = true
        while changed {
            changed = false
            for lock in remainingLocks {
                let candidate = unlock(current, at: lock)
                if isUniquelySolvable(candidate, mode: mode) {
                    current = candidate
                    remainingLocks.removeAll { $0.r == lock.r && $0.c == lock.c }
                    changed = true
                    break
                }
            }
        }
        return remainingLocks
    }

    /// How many locks could be removed while preserving uniqueness.
    /// Higher numbers indicate the generator gave more-than-minimum
    /// hints — useful for difficulty scoring later.
    static func minimumLockCount(_ puzzle: Puzzle, mode: CBMode = .none) -> Int {
        minimumLockSet(puzzle, mode: mode).count
    }

    /// Return a copy of `puzzle` with the cell at (r,c) converted from
    /// locked → free. Rebuilds the bank by appending that cell's
    /// solution color. No-op if the cell isn't a locked cell.
    private static func unlock(_ puzzle: Puzzle,
                               at coord: (r: Int, c: Int)) -> Puzzle {
        var out = puzzle
        var addedBankColor: OKLCh? = nil
        // Update all gradients covering this cell.
        for gi in 0..<out.gradients.count {
            var g = out.gradients[gi]
            for si in 0..<g.cells.count
            where g.cells[si].r == coord.r && g.cells[si].c == coord.c {
                if g.cells[si].locked {
                    g.cells[si].locked = false
                    addedBankColor = g.cells[si].color
                }
            }
            out.gradients[gi] = g
        }
        if out.board.indices.contains(coord.r),
           out.board[coord.r].indices.contains(coord.c) {
            var cell = out.board[coord.r][coord.c]
            if cell.locked {
                cell.locked = false
                cell.placed = nil
                out.board[coord.r][coord.c] = cell
            }
        }
        if let color = addedBankColor {
            let maxId = out.bank.compactMap { $0?.id }.max() ?? -1
            out.bank.append(BankItem(id: maxId + 1, color: color))
            out.initialBankCount = out.bank.count
        }
        return out
    }

    /// Returns an `AmbiguityReport` if the puzzle admits >1 distinct
    /// placement, or `nil` if it is uniquely solvable. The report
    /// includes the specific cells that differ between canonical and
    /// alternate placements, the gradients involved, and a
    /// best-guess classification.
    static func diagnose(_ puzzle: Puzzle, mode: CBMode = .none) -> AmbiguityReport? {
        let matchings = findPlacements(puzzle, mode: mode, limit: 2)
        guard matchings.count >= 2 else { return nil }

        // Recover cell index → (r,c,solution) ordering so we can
        // map the assignment arrays back to coordinates.
        let freeCells = extractFreeCells(puzzle)
        let bankColors: [OKLCh] = puzzle.bank.compactMap { $0?.color }

        func placement(from assignment: [Int]) -> [(r: Int, c: Int, color: OKLCh)] {
            return assignment.enumerated().map { (j, i) in
                (freeCells[j].r, freeCells[j].c, bankColors[i])
            }
        }

        // Treat the first matching whose per-cell colors best match
        // each cell's spec.color as "canonical." If none does better
        // than another, fall back to matchings[0].
        let canonical = pickCanonical(matchings: matchings,
                                       freeCells: freeCells,
                                       bankColors: bankColors,
                                       mode: mode)
        let alternate = matchings.first { $0 != canonical }!

        let canonicalMap = placement(from: canonical)
        let alternateMap = placement(from: alternate)

        var diffs: [AmbiguityReport.CellDiff] = []
        for j in 0..<freeCells.count {
            let canColor = bankColors[canonical[j]]
            let altColor = bankColors[alternate[j]]
            if !OK.equal(canColor, altColor, mode: mode) {
                diffs.append(AmbiguityReport.CellDiff(
                    r: freeCells[j].r, c: freeCells[j].c,
                    canonical: canColor,
                    alternate: altColor,
                    solution: freeCells[j].solution))
            }
        }

        let gradIds = gradientIds(coveringCells: diffs, puzzle: puzzle)
        let kind = classify(diffs: diffs, involvedGradIds: gradIds,
                            puzzle: puzzle, mode: mode)

        return AmbiguityReport(
            kind: kind,
            involvedGradientIds: gradIds,
            differingCells: diffs,
            canonicalPlacement: canonicalMap,
            alternatePlacement: alternateMap)
    }

    // MARK: — internals

    /// Enumerate up to `limit` distinct visible placements. Each
    /// placement is returned as an assignment vector
    /// `assignment[cellIdx] = bankIdx`, where the cell order is the
    /// `extractFreeCells(puzzle)` order.
    private static func findPlacements(_ puzzle: Puzzle,
                                       mode: CBMode,
                                       limit: Int,
                                       enforceStepConsistency: Bool = true) -> [[Int]] {
        let freeCells = extractFreeCells(puzzle)
        let n = freeCells.count

        let bankColors: [OKLCh] = puzzle.bank.compactMap { $0?.color }
        guard bankColors.count == n else { return [] }

        // Locked-cell internal-consistency check.
        var lockMap: [Int: OKLCh] = [:]
        for g in puzzle.gradients {
            for spec in g.cells where spec.locked {
                let key = spec.r * 64 + spec.c
                if let existing = lockMap[key] {
                    if !OK.equal(existing, spec.color, mode: mode) { return [] }
                } else {
                    lockMap[key] = spec.color
                }
            }
        }

        // Adjacency.
        var adj: [[Int]] = Array(repeating: [], count: n)
        for j in 0..<n {
            for i in 0..<n where OK.equal(bankColors[i], freeCells[j].solution, mode: mode) {
                adj[j].append(i)
            }
        }

        // ΔE-equivalence classes on bank colors.
        let labels = buildBankClasses(bankColors: bankColors, mode: mode)

        // Backtrack. Visit cells with the fewest options first.
        let order = (0..<n).sorted { adj[$0].count < adj[$1].count }
        var used = Array(repeating: false, count: n)
        var assignment: [Int] = Array(repeating: -1, count: n)
        var distinctByVector: [[Int]: [Int]] = [:]  // class-vector → first assignment seen
        var done = false

        func backtrack(_ depth: Int) {
            if done { return }
            if depth == n {
                // Rule 2 gate — check adjacency step consistency BEFORE
                // recording this matching. An assignment that passes
                // per-cell OK.equal but violates the step rule is not
                // a valid placement.
                if enforceStepConsistency {
                    if !stepConsistent(assignment: assignment,
                                        freeCells: freeCells,
                                        bankColors: bankColors,
                                        puzzle: puzzle, mode: mode) {
                        return
                    }
                }
                let vec = (0..<n).map { labels[assignment[$0]] }
                if distinctByVector[vec] == nil {
                    distinctByVector[vec] = assignment
                    if distinctByVector.count >= limit { done = true }
                }
                return
            }
            let j = order[depth]
            for i in adj[j] {
                if used[i] { continue }
                used[i] = true
                assignment[j] = i
                backtrack(depth + 1)
                used[i] = false
                assignment[j] = -1
                if done { return }
            }
        }
        backtrack(0)

        return Array(distinctByVector.values)
    }

    /// Rule 2 check — for every consecutive cell pair on every
    /// gradient, the delta between placed colors must equal that
    /// gradient's step vector within ΔE 2. Palindromic gradients
    /// satisfy both ±step, so the check accepts reversed placements
    /// only on truly palindromic color sequences (which guard 3.5 in
    /// Generate.swift rejects — so they shouldn't reach the solver).
    private static func stepConsistent(
        assignment: [Int],
        freeCells: [(r: Int, c: Int, solution: OKLCh)],
        bankColors: [OKLCh],
        puzzle: Puzzle,
        mode: CBMode
    ) -> Bool {
        // (r,c) → placed color (locked cells use spec.color; free
        // cells use bank[assignment[j]]).
        var placed: [Int: OKLCh] = [:]  // key = r*64 + c
        for g in puzzle.gradients {
            for spec in g.cells where spec.locked {
                placed[spec.r * 64 + spec.c] = spec.color
            }
        }
        for j in freeCells.indices {
            let c = freeCells[j]
            placed[c.r * 64 + c.c] = bankColors[assignment[j]]
        }
        for g in puzzle.gradients where g.cells.count >= 2 {
            // Gradients are linear in OKLCh, not OKLab — so the
            // expected lab-delta between consecutive cells varies per
            // position (pure-hue steps project to curved arcs in a/b).
            // Use the SPEC delta at each position as ground truth and
            // compare against the PLACED delta.
            let byPos = g.cells.sorted { $0.pos < $1.pos }
            for i in 0..<(byPos.count - 1) {
                let c0 = byPos[i], c1 = byPos[i + 1]
                guard let p0 = placed[c0.r * 64 + c0.c],
                      let p1 = placed[c1.r * 64 + c1.c] else {
                    return false
                }
                // Expected delta at this position = spec[i+1] - spec[i].
                let s0 = labUnder(c0.color, mode: mode)
                let s1 = labUnder(c1.color, mode: mode)
                let sL = s1.L - s0.L, sA = s1.a - s0.a, sB = s1.b - s0.b
                // Actual delta under the placement.
                let l0 = labUnder(p0, mode: mode)
                let l1 = labUnder(p1, mode: mode)
                let dL = l1.L - l0.L, dA = l1.a - l0.a, dB = l1.b - l0.b
                // ΔE between deltas, in ΔE-2 tolerance (lab ×100).
                let eL = (dL - sL) * 100
                let eA = (dA - sA) * 100
                let eB = (dB - sB) * 100
                if sqrt(eL * eL + eA * eA + eB * eB) >= 2 { return false }
            }
        }
        return true
    }

    private static func extractFreeCells(
        _ puzzle: Puzzle
    ) -> [(r: Int, c: Int, solution: OKLCh)] {
        var freeCells: [(r: Int, c: Int, solution: OKLCh)] = []
        var seen: Set<Int> = []
        for g in puzzle.gradients {
            for spec in g.cells where !spec.locked {
                let key = spec.r * 64 + spec.c
                if seen.contains(key) { continue }
                seen.insert(key)
                freeCells.append((spec.r, spec.c, spec.color))
            }
        }
        return freeCells
    }

    private static func buildBankClasses(bankColors: [OKLCh],
                                          mode: CBMode) -> [Int] {
        let n = bankColors.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            var c = x
            while parent[c] != c { let nx = parent[c]; parent[c] = r; c = nx }
            return r
        }
        for i in 0..<n {
            for k in (i + 1)..<n where OK.equal(bankColors[i], bankColors[k], mode: mode) {
                let ri = find(i), rk = find(k)
                if ri != rk { parent[ri] = rk }
            }
        }
        var labelOf: [Int: Int] = [:]
        var next = 0
        var labels = Array(repeating: -1, count: n)
        for i in 0..<n {
            let r = find(i)
            if let l = labelOf[r] {
                labels[i] = l
            } else {
                labelOf[r] = next
                labels[i] = next
                next += 1
            }
        }
        return labels
    }

    /// Pick the matching whose placed colors hew closest to each cell's
    /// spec.color. For the generator's construction this is always the
    /// canonical "bank item j lands on cell j" assignment (modulo the
    /// solver's internal ordering).
    private static func pickCanonical(
        matchings: [[Int]],
        freeCells: [(r: Int, c: Int, solution: OKLCh)],
        bankColors: [OKLCh],
        mode: CBMode
    ) -> [Int] {
        var best = matchings[0]
        var bestScore = Double.infinity
        for m in matchings {
            var s = 0.0
            for j in 0..<freeCells.count {
                s += OK.dist(bankColors[m[j]], freeCells[j].solution, mode: mode)
            }
            if s < bestScore { bestScore = s; best = m }
        }
        return best
    }

    private static func gradientIds(
        coveringCells diffs: [AmbiguityReport.CellDiff],
        puzzle: Puzzle
    ) -> [Int] {
        var ids: Set<Int> = []
        for d in diffs {
            if let cell = (puzzle.board.indices.contains(d.r)
                           ? puzzle.board[d.r].indices.contains(d.c)
                             ? puzzle.board[d.r][d.c]
                             : nil
                           : nil) {
                for gid in cell.gradIds { ids.insert(gid) }
            }
        }
        return ids.sorted()
    }

    /// Heuristic classifier. Looks at which gradients the differing
    /// cells sit on and whether the alternate colors form a reversal
    /// of the canonical colors within a single gradient.
    private static func classify(
        diffs: [AmbiguityReport.CellDiff],
        involvedGradIds: [Int],
        puzzle: Puzzle,
        mode: CBMode
    ) -> AmbiguityReport.Kind {
        guard !diffs.isEmpty else { return .unknown }

        if involvedGradIds.count == 1, let gid = involvedGradIds.first,
           let g = puzzle.gradients.first(where: { $0.id == gid }) {
            // Gradient-local analysis. Three questions:
            //   1. Are the gradient's own solution colors perceptually
            //      palindromic? (solution[i] ≈ solution[len-1-i] for all i)
            //   2. Does the alternate placement arrange bank items in
            //      the exact reverse-positions of the canonical?
            //   3. Do the diffs cover every free cell on the gradient?
            // All three true → palindromicGradient (guard 3.5 miss).
            // (2) and (3) but not (1) → partialGradientReversal / swap
            //   of items the bank happens to accept both ways, which
            //   is a bank-cross-match dressed up as a reversal. Label
            //   it bankCrossMatch.
            let solutionPalindrome = (0..<(g.len / 2)).allSatisfy { i in
                OK.equal(g.colors[i], g.colors[g.len - 1 - i], mode: mode)
            }
            var posMap: [Int: (can: OKLCh, alt: OKLCh)] = [:]
            for d in diffs {
                if let spec = g.cells.first(where: { $0.r == d.r && $0.c == d.c }) {
                    posMap[spec.pos] = (d.canonical, d.alternate)
                }
            }
            let coversWholeGradient = diffs.count == g.cells.filter { !$0.locked }.count
            let alternateIsReversal = coversWholeGradient &&
                posMap.allSatisfy { (pos, pair) in
                    if let mirror = posMap[g.len - 1 - pos] {
                        return OK.equal(pair.alt, mirror.can, mode: mode)
                    }
                    return false
                }

            if solutionPalindrome && alternateIsReversal {
                return .palindromicGradient
            }
            if alternateIsReversal {
                // Reversal-shaped but gradient isn't actually palindromic.
                // Means some other mechanism (bank crossmatch that
                // happens to look like a reversal on this small
                // gradient) is producing the ambiguity.
                return .bankCrossMatch
            }
            return .partialGradientReversal
        }

        return .bankCrossMatch
    }
}
