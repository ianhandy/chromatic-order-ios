//  VoiceOver reads this game's only content: colour. `OK.spokenName` is
//  what turns a cell or a swatch into something a player who can't see the
//  board can choose between, so it is pinned here against the actual sRGB
//  primaries rather than against the band table it is implemented with.

import XCTest
@testable import ChromaticOrder

final class SpokenColorTests: XCTestCase {

    /// Linear-RGB primaries are the same triples as their sRGB encodings,
    /// so these are exactly "pure red", "pure green" and so on.
    private func named(_ r: Double, _ g: Double, _ b: Double) -> String {
        OK.spokenName(OK.fromLinearRGB((r: r, g: g, b: b)))
    }

    func testPrimariesGetTheNameAPlayerWouldUse() {
        XCTAssertTrue(named(1, 0, 0).contains("red"), named(1, 0, 0))
        XCTAssertTrue(named(0, 1, 0).contains("green"), named(0, 1, 0))
        XCTAssertTrue(named(0, 0, 1).contains("blue"), named(0, 0, 1))
        XCTAssertTrue(named(1, 1, 0).contains("yellow"), named(1, 1, 0))
        XCTAssertTrue(named(0, 1, 1).contains("teal"), named(0, 1, 1))
        XCTAssertTrue(named(1, 0, 1).contains("pink"), named(1, 0, 1))
        // Between red and yellow, and between blue and pink.
        XCTAssertTrue(named(1, 0.35, 0).contains("orange"), named(1, 0.35, 0))
        XCTAssertTrue(named(0.35, 0, 1).contains("purple"), named(0.35, 0, 1))
    }

    /// Lightness is the other half of the description: a ramp is mostly the
    /// same hue getting lighter, so "blue" alone would name every cell in it.
    func testLightnessQualifiesTheHue() {
        let hue = 264.0   // sRGB blue
        XCTAssertEqual(OK.spokenName(OKLCh(L: 0.30, c: 0.15, h: hue)), "dark blue")
        XCTAssertEqual(OK.spokenName(OKLCh(L: 0.55, c: 0.15, h: hue)), "blue")
        XCTAssertEqual(OK.spokenName(OKLCh(L: 0.80, c: 0.15, h: hue)), "light blue")
    }

    /// Under the chroma floor there is no hue worth naming — calling a
    /// near-neutral cell "blue" would send a player looking for a blue one.
    func testNearNeutralsAreGray() {
        XCTAssertEqual(OK.spokenName(OKLCh(L: 0.30, c: 0.01, h: 264)), "dark gray")
        XCTAssertEqual(OK.spokenName(OKLCh(L: 0.55, c: 0.01, h: 264)), "gray")
        XCTAssertEqual(OK.spokenName(OKLCh(L: 0.80, c: 0.01, h: 264)), "light gray")
    }

    /// Hue is an angle, so the wrap-around band is the one that breaks.
    func testHueWrapsWithoutFallingOffTheTable() {
        let vocabulary: Set<String> = [
            "pink", "red", "orange", "yellow", "green", "teal", "blue", "purple",
        ]
        for degrees in stride(from: -720.0, through: 1080.0, by: 3.0) {
            let name = OK.spokenName(OKLCh(L: 0.55, c: 0.15, h: degrees))
            XCTAssertTrue(vocabulary.contains(name),
                          "hue \(degrees) spoke as '\(name)'")
        }
    }

    /// The real corpus: every colour the campaign actually shows a player
    /// has to come out with a usable name, including its bank swatches.
    func testEveryCampaignColorHasASpokenName() throws {
        let vocabulary: Set<String> = [
            "pink", "red", "orange", "yellow", "green", "teal", "blue", "purple",
            "gray",
        ]
        var seen: Set<String> = []
        for entry in CampaignCatalog.levels {
            let puzzle = try XCTUnwrap(entry.puzzle(), "level \(entry.index)")
            var colors: [OKLCh] = puzzle.bank.compactMap { $0?.color }
            for row in puzzle.board {
                for cell in row {
                    if let solution = cell.solution { colors.append(solution) }
                }
            }
            XCTAssertFalse(colors.isEmpty, "level \(entry.index) has no colours")
            for color in colors {
                let name = OK.spokenName(color)
                seen.insert(name)
                let family = name.replacingOccurrences(of: "dark ", with: "")
                    .replacingOccurrences(of: "light ", with: "")
                XCTAssertTrue(vocabulary.contains(family),
                              "level \(entry.index) spoke a colour as '\(name)'")
            }
        }
        // A campaign that only ever spoke two or three names would mean the
        // bands are too coarse to orient with, whatever the vocabulary says.
        XCTAssertGreaterThan(seen.count, 8,
                             "campaign only ever speaks \(seen.sorted())")
    }
}
