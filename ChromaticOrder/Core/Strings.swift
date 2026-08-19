//  Central catalog of player-facing text. Everything the user reads
//  on screen should live here — menus, overlays, tutorials, prompts,
//  button labels, tab titles. Edit this single file to reskin the
//  game's tone or style without touching view code.
//
//  Conventions:
//  • Lowercase first-word labels match the game's existing style
//    (the menu wordmark and button labels are all lowercased). Use
//    sentence casing only for longer prose body text.
//  • Unicode arrows / glyphs stay inline so developers don't have to
//    chase escape codes elsewhere.
//  • Strings grouped by screen / feature in nested enums for fast
//    navigation. Prefer adding a new enum over a deep mixed bag.
//  • Multi-string content (tutorial page sets) lives as arrays so
//    adding / re-ordering pages is a one-spot edit.

import Foundation

enum Strings {

    // MARK: – Main menu

    enum Menu {
        static let title = "kromatika"
        static let campaign = "campaign"
        static let zen = "zen"
        static let challenge = "challenge"
        static let todaysPuzzle = "today's puzzle"
        static let gallery = "gallery"
        /// One name for one destination. The main menu used to say
        /// "options", the in-game menu "settings", and the sheet itself
        /// "Accessibility" — three labels for the same screen.
        static let settings = "settings"
        static let leaderboard = "leaderboard"
        static let stats = "stats"
        static let feedback = "feedback"
        static let rateUs = "rate us"
        static let rateUsPlease = "rate us, please?"
        static let oneRun = "one run"
        // Shown once, at the moment the player spends a free run — not
        // parked on the menu. The body has to answer the two questions a
        // player actually has: how much do i get, and when does it stop.
        static let trialTitleZen = "zen is part of the full version"
        static let trialTitleChallenge = "challenge is part of the full version"
        static let trialOfferBody = "this run is on me — play as many levels as you like. it ends when you leave for the menu."
        static let trialAccept = "start my free run"
    }

    // MARK: – Top bar

    enum TopBar {
        static let zenMode = "zen mode"
        static let todaysPuzzle = "today's puzzle"
        /// Rendered when checks hit zero — the heart glyph is kept
        /// inline so "0 ♥" formats consistently with the hearts row.
        static let noHearts = "0 \u{2665}"
    }

    // MARK: – Hamburger menu rows

    enum Hamburger {
        static let home = "home"
        static let settings = "settings"
        static let feedback = "feedback"
        static let share = "share"
        static let sharePreparing = "preparing…"
    }

    // MARK: – Solved overlay

    enum Solved {
        static let perfect = "perfect"
        static let nextLevel = "next level \u{2192}"
        static let backToMenu = "back to menu \u{2192}"
    }

    // MARK: – Challenge run complete

    enum RunComplete {
        static let title = "run complete!"
        static let levelsComplete = "levels complete"
        static let backToMenu = "back to menu \u{2192}"
    }

    // MARK: – Like / dislike feedback widget

    /// Floating per-level reaction prompt (good-level smiley /
    /// bad-level frowny). Kept terse — the row is competing with the
    /// solved-grid overlay for attention.
    enum LikeFeedback {
        // "good level?" got cut off in narrower widget layouts, where
        // the trailing arrow buttons crowd the prompt against the
        // capsule edge. The shorter form survives the squeeze.
        static let prompt = "good?"
    }

    // MARK: – One-time enjoyment prompt

    enum EnjoymentPrompt {
        static let question = "are you enjoying the game?"
        static let yes = "yes"
        static let no = "no"
        static let stopTalking = "stop talking to me"
        static let good = "good"
        static let sorry = "sorry"
        static let okay = "ok"
        static let justKidding = "…just kidding"
    }

    // MARK: – Tutorial tooltips

    /// Short capsule tooltips shown once per mode. Kept terse so
    /// they fit in the whitespace around the board without covering
    /// cells or swatches — the full how-to-play explainer lives in
    /// the help sheet, not here.
    enum TutorialTooltips {
        static let challenge = "drag a color\nup to a matching cell"
        static let zen = "tap here\nto change levels"
        static let daily = "one puzzle per day,\nsame for everyone"
    }

    // MARK: – Daily show-answers prompt

    enum DailyPrompt {
        static let title = "show answers?"
        static let body = "reveals cells that don't match the solution. turning this on disables leaderboard submission for today's puzzle."
        static let keepHidden = "keep hidden"
        static let enable = "show — skip leaderboard"
    }

    // MARK: – Tutorial-page button labels

    enum TutorialOverlay {
        static let next = "next \u{2192}"
        static let gotIt = "got it"
    }
}
