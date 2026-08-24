//  Every string VoiceOver is allowed to speak for a board cell, a bank
//  swatch, or the outcome of an attempt.
//
//  The rule this file exists to enforce
//  ────────────────────────────────────
//  Kromatika's whole puzzle is "which colour goes where". A spoken hue, a
//  colour family, a lightness qualifier, a temperature, a name for a
//  near-neutral — any of them hands a VoiceOver player a fact a sighted
//  player has to earn by eye, and on a short ramp it hands over the answer
//  outright. So VoiceOver gets everything *except* colour: where the cell
//  is, what state it is in, what the control does, and whether the attempt
//  worked.
//
//  None of the functions below takes a colour, and none of them can reach
//  one. That is deliberate, and it is the real guarantee: the signature
//  cannot express the leak, so no future edit inside a view can reintroduce
//  it without changing this file. `VoiceOverFairnessTests` enumerates the
//  complete output set — the inputs are booleans, so "complete" is literal
//  — and pins it against a colour vocabulary.
//
//  What is *not* colour, and is therefore spoken:
//
//  • Position — "row 2, column 3" never moves and never implies a value.
//  • State — empty / filled / fixed / selected / picked up / hinted. Each
//    is something the board already shows: an empty slot's dashed outline,
//    a fixed cell's centre dot, a picked-up swatch's lift and shadow, the
//    hint's white ring.
//  • Control semantics — the cells and slots are driven by a DragGesture,
//    which VoiceOver cannot perform, so the hint has to say what the
//    double-tap will actually do.
//  • Errors and success — "incorrect" mirrors the red outline, which only
//    appears after the player spends a Check, and disappears with it. It
//    says a placement is wrong; it never says what would be right.

import Foundation

enum BoardAccessibility {

    // ─── Cells ──────────────────────────────────────────────────────

    /// What the player can currently do with a cell. Drives the hint,
    /// because a double-tap means three different things depending on
    /// whether something is already in hand.
    enum Interaction {
        /// Nothing is in hand and the board is live.
        case idle
        /// A swatch (from the bank or another cell) is picked up.
        case holdingSwatch
        /// Board is finished — nothing moves any more.
        case boardFinished
    }

    /// Everything about a cell that VoiceOver is allowed to know.
    /// Deliberately all booleans: there is nowhere here to put a colour.
    struct CellFacts: Equatable {
        var locked: Bool = false
        var filled: Bool = false
        var selected: Bool = false
        var hinted: Bool = false
        /// The red outline is showing on this cell. Only ever true while
        /// `showIncorrect` is on, i.e. while the sighted player can see
        /// the same outline.
        var incorrect: Bool = false
    }

    /// Position only, and 1-based so it matches how a player counts.
    /// Stable for the life of the board: it does not change when a
    /// swatch lands, so VoiceOver focus never jumps to a renamed element.
    static func cellLabel(row: Int, column: Int) -> String {
        "cell, row \(row + 1), column \(column + 1)"
    }

    /// State only, in a fixed order so the phrasing is predictable:
    /// what the cell is, then what has been done to it.
    static func cellValue(_ facts: CellFacts) -> String {
        var parts: [String] = [
            facts.locked ? "fixed" : (facts.filled ? "filled" : "empty")
        ]
        if facts.hinted { parts.append("hinted") }
        if facts.selected { parts.append("selected") }
        if facts.incorrect { parts.append("incorrect") }
        return parts.joined(separator: ", ")
    }

    /// What the double-tap does. Empty when there is nothing to say —
    /// SwiftUI treats an empty hint as no hint.
    static func cellHint(_ facts: CellFacts, interaction: Interaction) -> String {
        guard interaction != .boardFinished, !facts.locked else { return "" }
        switch interaction {
        case .holdingSwatch:
            return facts.selected
                ? "double tap to put this swatch back down"
                : "double tap to place the picked-up swatch here"
        case .idle:
            return facts.filled
                ? "double tap to pick up this swatch"
                : "pick up a swatch first"
        case .boardFinished:
            return ""
        }
    }

    // ─── Bank slots ─────────────────────────────────────────────────

    struct SlotFacts: Equatable {
        var occupied: Bool = false
        var picked: Bool = false
        var hinted: Bool = false
    }

    /// Slot number, not contents. An occupied slot is "swatch 3" rather
    /// than anything about the swatch — the number is what stays put
    /// while the player moves swatches around it.
    static func slotLabel(slot: Int, occupied: Bool) -> String {
        occupied ? "swatch \(slot + 1)" : "empty slot \(slot + 1)"
    }

    static func slotValue(_ facts: SlotFacts) -> String {
        guard facts.occupied else { return "" }
        var parts: [String] = []
        if facts.hinted { parts.append("hinted") }
        if facts.picked { parts.append("picked up") }
        return parts.joined(separator: ", ")
    }

    static func slotHint(_ facts: SlotFacts, interaction: Interaction) -> String {
        guard interaction != .boardFinished else { return "" }
        switch interaction {
        case .holdingSwatch:
            return facts.picked
                ? "double tap to put this swatch back down"
                : "double tap to move the picked-up swatch here"
        case .idle:
            return facts.occupied ? "double tap to pick up this swatch" : ""
        case .boardFinished:
            return ""
        }
    }

    // ─── Outcomes ───────────────────────────────────────────────────
    //
    // The solve fired a glow, a squish, a chord and a haptic, and swapped
    // the bank for a row of buttons — all of it visual, audible or felt,
    // none of it spoken. A failed check fired red outlines that a
    // VoiceOver player would only find by walking the board.

    /// `revealed` is the challenge-mode failure and the manual peek: the
    /// board is finished but the player did not finish it, and calling
    /// that "solved" would be a lie told only to VoiceOver.
    static func solveAnnouncement(perfect: Bool, revealed: Bool) -> String {
        if revealed { return "solution revealed" }
        return perfect ? "solved, perfect" : "solved"
    }

    /// Spoken when the red outlines come on. The count is the number of
    /// outlines on screen — it says how many placements are wrong, never
    /// which colour any of them should have been.
    static func failedCheckAnnouncement(incorrectCount: Int) -> String {
        guard incorrectCount > 0 else { return "not solved yet" }
        let noun = incorrectCount == 1 ? "placement" : "placements"
        return "not solved yet, \(incorrectCount) \(noun) incorrect"
    }
}
