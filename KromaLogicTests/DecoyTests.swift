//  Red-herring gates.
//
//  A decoy is a bank swatch that belongs in no cell. That breaks the
//  oldest invariant in the game — "every swatch you were given is used"
//  — which was one of the three things a player could check to know they
//  were finished. Taking it away is only fair if the decoy is provably
//  rejectable, so these tests hold the shipped campaign to the two
//  properties the authoring tool claims it enforced:
//
//    1. The decoy is far enough from every real colour to be SEEN as a
//       different colour. If it sits inside the board's own perceptual
//       floor of some real cell, the player cannot tell them apart and
//       the level is a coin flip with no tell.
//
//    2. Dropping the decoy into any free cell leaves that gradient NOT
//       reading as an even walk. Otherwise the board can look finished
//       while being wrong, which is worse than a coin flip: it looks
//       like a win.
//
//  Both run in OKLab ΔE rather than raw channel deltas, because "far
//  enough" and "wrong enough" have to mean far and wrong *to a person*.
//  The whole mechanic rests on that distinction, so the test does too.

import XCTest

final class DecoyTests: XCTestCase {

    /// Every decoy the campaign ships, with the board it belongs to.
    private func campaignDocsWithDecoys() throws -> [(level: Int, doc: CreatorPuzzleDoc)] {
        let url = try XCTUnwrap(
            Bundle(for: DecoyTests.self).url(forResource: "campaign", withExtension: "json")
                ?? URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()      // KromaLogicTests
                    .deletingLastPathComponent()      // repo root
                    .appendingPathComponent("ChromaticOrder/Resources/campaign.json"),
            "campaign.json not found")
        struct Campaign: Codable {
            struct Level: Codable { let index: Int; let doc: CreatorPuzzleDoc }
            let levels: [Level]
        }
        let campaign = try JSONDecoder().decode(Campaign.self, from: Data(contentsOf: url))
        return campaign.levels
            .filter { !($0.doc.decoys ?? []).isEmpty }
            .map { ($0.index, $0.doc) }
    }

    /// Does this sequence read as one even walk? Mirrors the authoring
    /// tool's test, in Lab, at the same tolerance.
    private func readsEvenly(_ values: [OKLCh]) -> Bool {
        guard values.count >= 3 else { return true }
        let labs = values.map { OK.toLab($0) }
        let first = (labs[1].L - labs[0].L, labs[1].a - labs[0].a, labs[1].b - labs[0].b)
        for i in 1..<(values.count - 1) {
            let step = (labs[i + 1].L - labs[i].L,
                        labs[i + 1].a - labs[i].a,
                        labs[i + 1].b - labs[i].b)
            let gap = sqrt(pow((step.0 - first.0) * 100, 2)
                           + pow((step.1 - first.1) * 100, 2)
                           + pow((step.2 - first.2) * 100, 2))
            if gap >= 2 { return false }
        }
        return true
    }

    /// The campaign actually ships the mechanic. Guards against a
    /// regenerate that silently drops `decoys` from every doc and leaves
    /// the chapter as an ordinary one.
    func testCampaignShipsDecoys() throws {
        let withDecoys = try campaignDocsWithDecoys()
        XCTAssertFalse(withDecoys.isEmpty, "no campaign level ships a decoy")
        // They belong to the chapter built for them, not scattered into
        // levels that were balanced without them.
        for (level, _) in withDecoys {
            XCTAssertGreaterThanOrEqual(
                level, 201,
                "level \(level) ships a decoy but predates the mechanic's chapter")
        }
    }

    /// Property 1 — a decoy never impersonates a real colour.
    func testDecoysAreDistinguishableFromEveryRealColour() throws {
        for (level, doc) in try campaignDocsWithDecoys() {
            let reals = doc.gradients.flatMap { g in
                g.cells.map { OKLCh(L: $0.L, c: $0.C, h: $0.h) }
            }
            // The bar is the board's own worst real pair: a decoy must
            // never be closer to a real colour than two real colours are
            // to each other, or it is the hardest call on the board while
            // also being the one call that cannot be reasoned out.
            var tightestReal = Double.infinity
            let distinct = Dictionary(
                grouping: doc.gradients.flatMap { g in g.cells.map { ($0.r, $0.c, $0) } },
                by: { "\($0.0),\($0.1)" }
            ).values.compactMap { $0.first }.map { OKLCh(L: $0.2.L, c: $0.2.C, h: $0.2.h) }
            for i in 0..<distinct.count {
                for j in (i + 1)..<distinct.count {
                    tightestReal = min(tightestReal, OK.dist(distinct[i], distinct[j]))
                }
            }
            for d in doc.decoys ?? [] {
                let decoy = OKLCh(L: d.L, c: d.C, h: d.h)
                let nearest = reals.map { OK.dist(decoy, $0) }.min() ?? .infinity
                XCTAssertGreaterThanOrEqual(
                    nearest, tightestReal,
                    "level \(level): decoy sits ΔE \(nearest) from a real colour, "
                    + "closer than the board's own tightest real pair (\(tightestReal))")
            }
        }
    }

    /// Property 2 — a decoy is wrong in every cell it could be dropped
    /// into, and visibly so.
    func testDecoysBreakEveryRunTheyCouldBeDroppedInto() throws {
        for (level, doc) in try campaignDocsWithDecoys() {
            for d in doc.decoys ?? [] {
                let decoy = OKLCh(L: d.L, c: d.C, h: d.h)
                for (gi, g) in doc.gradients.enumerated() {
                    let cols = g.cells.map { OKLCh(L: $0.L, c: $0.C, h: $0.h) }
                    for (pos, cell) in g.cells.enumerated() where !(cell.locked ?? false) {
                        var trial = cols
                        trial[pos] = decoy
                        XCTAssertFalse(
                            readsEvenly(trial),
                            "level \(level): decoy dropped at gradient \(gi) pos \(pos) "
                            + "still reads as an even walk — the board would look finished "
                            + "while being wrong")
                    }
                }
            }
        }
    }

    /// The decoded puzzle actually carries its decoys into the bank, and
    /// keeps a record of them. Reset rebuilds the bank from the board's
    /// solution cells, so without that record the spares would vanish the
    /// first time a player reset and the level would get easier.
    func testDecodedPuzzleBanksAndRemembersDecoys() throws {
        for (level, doc) in try campaignDocsWithDecoys() {
            let puzzle = try XCTUnwrap(
                CreatorCodec.rebuild(doc, level: level),
                "level \(level) failed to decode")
            let decoyCount = (doc.decoys ?? []).count
            XCTAssertEqual(
                puzzle.decoys.count, decoyCount,
                "level \(level): puzzle lost its decoy record, Reset would drop them")

            var freeCells = Set<String>()
            for g in doc.gradients {
                for c in g.cells where !(c.locked ?? false) { freeCells.insert("\(c.r),\(c.c)") }
            }
            XCTAssertEqual(
                puzzle.bank.compactMap { $0 }.count, freeCells.count + decoyCount,
                "level \(level): bank should hold one swatch per free cell plus every decoy")
        }
    }
}
