//  Fairness, not coverage.
//
//  Kromatika's puzzle is "which colour goes where". A sighted player has to
//  work that out by comparing swatches by eye; if VoiceOver names a colour
//  — a hue, a family, a lightness, a temperature, "gray" — it hands over
//  the comparison, and on a four-step ramp it hands over the answer. So the
//  bar these tests hold is not "VoiceOver says something useful" but
//  "VoiceOver cannot say a colour."
//
//  Three layers, deliberately overlapping:
//
//  1. Exhaustive. `BoardAccessibility`'s inputs are booleans, so the set of
//     strings it can EVER produce is finite and small enough to enumerate
//     completely. These tests enumerate it and pin every member.
//  2. Corpus. The same strings, built from the 200 shipped campaign boards,
//     and proven invariant under recolouring the whole board — if the
//     output does not change when the colours do, the output cannot be
//     carrying one.
//  3. Source audit. Every accessibility label, value, hint and announcement
//     on the play surfaces, read out of the sources, checked for any
//     expression that could reach a colour at all.

import XCTest
@testable import ChromaticOrder

final class VoiceOverFairnessTests: XCTestCase {

    // MARK: - The vocabulary that must never appear

    /// Colour identifiers: hue families, the lightness and saturation
    /// qualifiers that separate steps within one family, and the words the
    /// codebase uses for colour internally. Matched case-insensitively as
    /// whole words.
    private static let forbiddenWords: [String] = [
        // Hue families, plus the ones a future well-meaning edit reaches
        // for that this game's palette doesn't currently produce.
        "red", "orange", "amber", "yellow", "olive", "lime", "green",
        "mint", "teal", "cyan", "aqua", "turquoise", "blue", "azure",
        "indigo", "violet", "purple", "magenta", "pink", "rose", "crimson",
        "scarlet", "brown", "tan", "beige", "maroon", "navy", "gold",
        "silver", "black", "white", "gray", "grey", "neutral",
        // Lightness / saturation qualifiers. On a ramp these are the whole
        // puzzle: every cell in a run is the same family, and only these
        // would tell them apart.
        "dark", "darker", "darkest", "light", "lighter", "lightest",
        "pale", "bright", "brighter", "deep", "deeper", "dull", "vivid",
        "muted", "washed", "faded", "saturated", "desaturated",
        // Temperature and the internal vocabulary.
        "warm", "warmer", "cool", "cooler", "hue", "chroma", "luminance",
        "lightness", "saturation", "tint", "shade", "tone", "colour",
        "color", "colours", "colors", "oklch", "rgb", "hex",
    ]

    /// Splits on anything that isn't a letter so "dark blue," and
    /// "light-orange" both come apart into words.
    private func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
    }

    private func assertCarriesNoColor(_ text: String,
                                      _ context: @autoclosure () -> String,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let offenders = Set(words(in: text))
            .intersection(Self.forbiddenWords)
            .sorted()
        XCTAssertTrue(offenders.isEmpty,
                      "\(context()) — VoiceOver would speak \(offenders) in \"\(text)\"",
                      file: file, line: line)
    }

    // MARK: - 1. The complete output set

    private static let allInteractions: [BoardAccessibility.Interaction] =
        [.idle, .holdingSwatch, .boardFinished]

    /// Every combination of the five booleans a cell has.
    private var allCellFacts: [BoardAccessibility.CellFacts] {
        (0..<32).map { bits in
            BoardAccessibility.CellFacts(
                locked:    bits & 1 != 0,
                filled:    bits & 2 != 0,
                selected:  bits & 4 != 0,
                hinted:    bits & 8 != 0,
                incorrect: bits & 16 != 0
            )
        }
    }

    private var allSlotFacts: [BoardAccessibility.SlotFacts] {
        (0..<8).map { bits in
            BoardAccessibility.SlotFacts(
                occupied: bits & 1 != 0,
                picked:   bits & 2 != 0,
                hinted:   bits & 4 != 0
            )
        }
    }

    /// The inputs are booleans and a coordinate, so this is not a sample:
    /// it is every string a cell can ever produce, listed.
    func testEveryCellStringIsColorFree() {
        for row in 0..<24 {
            for column in 0..<24 {
                assertCarriesNoColor(BoardAccessibility.cellLabel(row: row, column: column),
                                     "cell label at \(row),\(column)")
            }
        }
        for facts in allCellFacts {
            assertCarriesNoColor(BoardAccessibility.cellValue(facts), "cell value \(facts)")
            for interaction in Self.allInteractions {
                assertCarriesNoColor(
                    BoardAccessibility.cellHint(facts, interaction: interaction),
                    "cell hint \(facts) / \(interaction)"
                )
            }
        }
    }

    func testEveryBankSlotStringIsColorFree() {
        for slot in 0..<64 {
            assertCarriesNoColor(BoardAccessibility.slotLabel(slot: slot, occupied: true),
                                 "occupied slot label \(slot)")
            assertCarriesNoColor(BoardAccessibility.slotLabel(slot: slot, occupied: false),
                                 "empty slot label \(slot)")
        }
        for facts in allSlotFacts {
            assertCarriesNoColor(BoardAccessibility.slotValue(facts), "slot value \(facts)")
            for interaction in Self.allInteractions {
                assertCarriesNoColor(
                    BoardAccessibility.slotHint(facts, interaction: interaction),
                    "slot hint \(facts) / \(interaction)"
                )
            }
        }
    }

    func testEveryAnnouncementIsColorFree() {
        for perfect in [true, false] {
            for revealed in [true, false] {
                let text = BoardAccessibility.solveAnnouncement(perfect: perfect,
                                                                revealed: revealed)
                assertCarriesNoColor(text, "solve announcement \(perfect)/\(revealed)")
            }
        }
        for count in 0...64 {
            assertCarriesNoColor(BoardAccessibility.failedCheckAnnouncement(incorrectCount: count),
                                 "failed check announcement \(count)")
        }
    }

    /// The whole vocabulary a cell or a slot can speak, gathered from the
    /// exhaustive sweep. Locked down so a new word has to be added here
    /// deliberately rather than slipping in behind a passing colour check.
    func testTheSpokenVocabularyIsTheExpectedShortList() {
        var vocabulary: Set<String> = []
        for facts in allCellFacts {
            vocabulary.formUnion(words(in: BoardAccessibility.cellValue(facts)))
            for interaction in Self.allInteractions {
                vocabulary.formUnion(
                    words(in: BoardAccessibility.cellHint(facts, interaction: interaction)))
            }
        }
        for facts in allSlotFacts {
            vocabulary.formUnion(words(in: BoardAccessibility.slotValue(facts)))
            for interaction in Self.allInteractions {
                vocabulary.formUnion(
                    words(in: BoardAccessibility.slotHint(facts, interaction: interaction)))
            }
        }
        vocabulary.formUnion(words(in: BoardAccessibility.cellLabel(row: 0, column: 0)))
        vocabulary.formUnion(words(in: BoardAccessibility.slotLabel(slot: 0, occupied: true)))
        vocabulary.formUnion(words(in: BoardAccessibility.slotLabel(slot: 0, occupied: false)))

        let expected: Set<String> = [
            // Position
            "cell", "row", "column", "swatch", "slot",
            // State
            "empty", "filled", "fixed", "hinted", "selected", "incorrect",
            "picked", "up",
            // Control semantics
            "double", "tap", "to", "place", "the", "this", "here", "move",
            "pick", "a", "first", "put", "back", "down",
        ]
        XCTAssertEqual(vocabulary, expected,
                       "board vocabulary drifted: added \(vocabulary.subtracting(expected).sorted()), "
                       + "dropped \(expected.subtracting(vocabulary).sorted())")
    }

    // MARK: - 2. The shipped corpus, and invariance under recolouring

    /// A bijection on colours: hue rotated by a number coprime with the
    /// circle's useful divisors, lightness mirrored. Applied to solutions,
    /// placements and bank items alike, so which cells MATCH is unchanged
    /// while every actual colour is different.
    private func recolored(_ color: OKLCh) -> OKLCh {
        OKLCh(L: 1 - color.L, c: color.c, h: OK.normH(color.h + 137))
    }

    private func recolored(_ puzzle: Puzzle) -> Puzzle {
        var copy = puzzle
        for r in copy.board.indices {
            for c in copy.board[r].indices {
                copy.board[r][c].solution = copy.board[r][c].solution.map(recolored)
                copy.board[r][c].placed = copy.board[r][c].placed.map(recolored)
            }
        }
        copy.bank = copy.bank.map { item in
            item.map { BankItem(id: $0.id, color: recolored($0.color)) }
        }
        return copy
    }

    /// Everything VoiceOver would say while walking one board, in order.
    /// Mirrors what CellView and BankSlotView build, including the two
    /// player-driven states (selection, hint) and the error markers, which
    /// are swept rather than sampled.
    private func transcript(of puzzle: Puzzle, showIncorrect: Bool) -> [String] {
        var lines: [String] = []
        for (r, row) in puzzle.board.enumerated() {
            for (c, cell) in row.enumerated() {
                guard cell.kind != .dead else { continue }   // hidden from VoiceOver
                let filled = cell.placed != nil
                // Exact equality rather than the game's ΔE test: the
                // recolouring is a bijection, so exact matches survive it
                // and the comparison stays deterministic in a unit test.
                let incorrect = showIncorrect && !cell.locked
                    && cell.placed != nil && cell.placed != cell.solution
                for selected in [false, true] {
                    for hinted in [false, true] {
                        let facts = BoardAccessibility.CellFacts(
                            locked: cell.locked, filled: filled,
                            selected: selected, hinted: hinted, incorrect: incorrect
                        )
                        lines.append(BoardAccessibility.cellLabel(row: r, column: c))
                        lines.append(BoardAccessibility.cellValue(facts))
                        for interaction in Self.allInteractions {
                            lines.append(BoardAccessibility.cellHint(facts,
                                                                     interaction: interaction))
                        }
                    }
                }
            }
        }
        for (slot, item) in puzzle.bank.enumerated() {
            for picked in [false, true] {
                for hinted in [false, true] {
                    let facts = BoardAccessibility.SlotFacts(
                        occupied: item != nil, picked: picked, hinted: hinted
                    )
                    lines.append(BoardAccessibility.slotLabel(slot: slot,
                                                              occupied: item != nil))
                    lines.append(BoardAccessibility.slotValue(facts))
                    for interaction in Self.allInteractions {
                        lines.append(BoardAccessibility.slotHint(facts,
                                                                 interaction: interaction))
                    }
                }
            }
        }
        return lines
    }

    /// The real thing: 200 authored boards, every cell, every slot, every
    /// player state, with the error markers both off and on.
    func testNoCampaignBoardSpeaksAColor() throws {
        XCTAssertFalse(CampaignCatalog.levels.isEmpty, "no campaign to audit")
        for entry in CampaignCatalog.levels {
            let puzzle = try XCTUnwrap(entry.puzzle(), "level \(entry.index) failed to load")
            for showIncorrect in [false, true] {
                for line in transcript(of: puzzle, showIncorrect: showIncorrect) {
                    assertCarriesNoColor(line, "campaign level \(entry.index)")
                }
            }
        }
    }

    /// The fairness proof. Recolour every board — solutions, placements
    /// and bank alike — and VoiceOver must say exactly the same words in
    /// exactly the same order. Output that does not move when the colours
    /// move cannot be carrying a colour, however it is phrased.
    func testVoiceOverOutputIsUnchangedByRecoloringTheBoard() throws {
        for entry in CampaignCatalog.levels {
            let puzzle = try XCTUnwrap(entry.puzzle(), "level \(entry.index) failed to load")
            let other = recolored(puzzle)
            for showIncorrect in [false, true] {
                XCTAssertEqual(transcript(of: puzzle, showIncorrect: showIncorrect),
                               transcript(of: other, showIncorrect: showIncorrect),
                               "level \(entry.index) reads differently after recolouring")
            }
        }
    }

    /// Same proof against a live board rather than a stored one: play a
    /// real puzzle through the state machine, then check that the facts
    /// the views feed VoiceOver still hold no colour.
    @MainActor
    func testLiveBoardStatesSpeakNoColor() throws {
        let game = GameState()
        XCTAssertTrue(game.loadCampaignLevel(1))
        let puzzle = try XCTUnwrap(game.puzzle)

        // Untouched, one swatch in hand, and one placed — the three shapes
        // the board takes while a player works.
        game.tapSlot(0)
        XCTAssertEqual(game.accessibilityInteraction, .holdingSwatch,
                       "picking a swatch up must change what a double-tap means")
        for line in transcript(of: puzzle, showIncorrect: false) {
            assertCarriesNoColor(line, "live board")
        }

        game.clearSelection()
        XCTAssertEqual(game.accessibilityInteraction, .idle)
        game.solved = true
        XCTAssertEqual(game.accessibilityInteraction, .boardFinished,
                       "a finished board offers no placement")
        CampaignStore.resetAll()
    }

    // MARK: - 3. Source audit

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ChromaticOrderTests
            .deletingLastPathComponent()      // repo root
    }

    /// The screens a player solves a puzzle on. The creator is excluded on
    /// purpose: an author is choosing the colours they are painting with,
    /// so naming a swatch there withholds nothing from anybody.
    private static let playSurfaces = [
        "ChromaticOrder/Views/CellView.swift",
        "ChromaticOrder/Views/SwatchView.swift",
        "ChromaticOrder/Views/GridView.swift",
        "ChromaticOrder/Views/BankView.swift",
        "ChromaticOrder/Views/TopBarView.swift",
        "ChromaticOrder/Views/CampaignTipBanner.swift",
        "ChromaticOrder/ContentView.swift",
        "ChromaticOrder/Core/BoardAccessibility.swift",
    ]

    /// Anything that can reach a colour value. A label built from one of
    /// these is a leak whatever it formats it into, so this catches the
    /// cases a word list cannot — `game.display(item.color)` never spells
    /// a colour out, it just speaks one.
    private static let colorBearingExpressions = [
        "spokenName", "OKLCh", "OK.", ".color", "heldColor", "activeColor",
        "display(", "solution", "placed", "shown", "toColor", "hueBands",
    ]

    /// The two views that render the puzzle itself, and the complete set
    /// of identifiers their accessibility strings are allowed to mention.
    ///
    /// A denylist can only catch the leaks somebody thought of; `shown`
    /// and `game.display(...)` are one rename apart from slipping past
    /// one. So the board's own views get the opposite rule: every name
    /// their labels, values and hints are built from has to appear here,
    /// and reaching for anything else — a colour, a solution, a bank item's
    /// contents — fails until it is added on purpose.
    private static let boardSurfaces = [
        "ChromaticOrder/Views/CellView.swift",
        "ChromaticOrder/Views/SwatchView.swift",
    ]

    private static let allowedBoardIdentifiers: Set<String> = [
        // The colour-free string builder and its entry points.
        "BoardAccessibility", "cellLabel", "cellValue", "cellHint",
        "slotLabel", "slotValue", "slotHint",
        // The per-view fact builders and the game's interaction mode.
        "accessibilityFacts", "accessibilityInteraction", "game",
        // Argument labels and the position / occupancy values behind them.
        "row", "column", "slot", "occupied", "filled", "interaction",
        "for", "item", "r", "c", "nil", "true", "false",
    ]

    /// Identifiers mentioned by a Swift expression, with string literals
    /// removed first so quoted prose doesn't read as code.
    private func identifiers(in expression: String) -> Set<String> {
        var stripped = ""
        var inString = false
        var previous: Character = " "
        for character in expression {
            if character == "\"", previous != "\\" { inString.toggle(); continue }
            if !inString { stripped.append(character) }
            previous = character
        }
        let names = stripped.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map(String.init)
        // Bare numbers aren't identifiers.
        return Set(names.filter { $0.first?.isNumber == false })
    }

    /// Every accessibility string on a play surface, extracted from the
    /// source with balanced parens so a nested call comes out whole.
    private func accessibilityArguments(in source: String) -> [(api: String, argument: String)] {
        let apis = [
            ".accessibilityLabel(", ".accessibilityValue(", ".accessibilityHint(",
            ".accessibilityInputLabels(", "AccessibilityNotification.Announcement(",
        ]
        var found: [(String, String)] = []
        let characters = Array(source)
        for api in apis {
            var searchStart = source.startIndex
            while let range = source.range(of: api, range: searchStart..<source.endIndex) {
                searchStart = range.upperBound
                var depth = 1
                var index = source.distance(from: source.startIndex, to: range.upperBound)
                let start = index
                var inString = false
                while index < characters.count, depth > 0 {
                    let character = characters[index]
                    if character == "\"" { inString.toggle() }
                    if !inString {
                        if character == "(" { depth += 1 }
                        if character == ")" { depth -= 1 }
                    }
                    index += 1
                }
                found.append((api, String(characters[start..<max(start, index - 1)])))
            }
        }
        return found
    }

    func testPlaySurfaceAccessibilityStringsCannotReachAColor() throws {
        var audited = 0
        for path in Self.playSurfaces {
            let url = repositoryRoot.appendingPathComponent(path)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("sources unavailable at \(url.path)")
            }
            for (api, argument) in accessibilityArguments(in: source) {
                audited += 1
                assertCarriesNoColor(argument, "\(path) \(api)")
                for expression in Self.colorBearingExpressions {
                    XCTAssertFalse(argument.contains(expression),
                                   "\(path) \(api) builds its text from `\(expression)`: "
                                   + "\(argument.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        XCTAssertGreaterThan(audited, 10,
                             "the audit found almost no accessibility strings — "
                             + "the extractor is probably broken, not the app clean")
    }

    /// The strict half: on the board itself, an accessibility string may
    /// only be built out of names on the allowlist.
    func testBoardAccessibilityStringsAreBuiltOnlyFromAllowedNames() throws {
        var audited = 0
        for path in Self.boardSurfaces {
            let url = repositoryRoot.appendingPathComponent(path)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("sources unavailable at \(url.path)")
            }
            for (api, argument) in accessibilityArguments(in: source) {
                audited += 1
                let unexpected = identifiers(in: argument)
                    .subtracting(Self.allowedBoardIdentifiers)
                    .sorted()
                XCTAssertTrue(unexpected.isEmpty,
                              "\(path) \(api) reaches for \(unexpected) — if that cannot "
                              + "carry a colour, add it to allowedBoardIdentifiers on purpose: "
                              + argument.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        XCTAssertEqual(audited, 6,
                       "expected a label, a value and a hint on each of the two board views")
    }

    /// The spoken-colour API itself, gone from the whole app rather than
    /// only from its call sites.
    func testNoSpokenColorAPISurvivesAnywhere() throws {
        let sources = repositoryRoot.appendingPathComponent("ChromaticOrder")
        guard let walker = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("sources unavailable at \(sources.path)")
        }
        var checked = 0
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(relative)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            checked += 1
            XCTAssertFalse(source.contains("spokenName"),
                           "\(relative) still references the spoken-colour API")
        }
        XCTAssertGreaterThan(checked, 50, "the source walk found almost nothing")
    }
}
