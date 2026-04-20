//  Small pure helpers — Swift port of src/util.js.
//  All randomness routes through GenRNG so the daily puzzle's seeded
//  override reaches every generator call site.

import Foundation

enum Util {
    static func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T {
        min(max(x, lo), hi)
    }

    static func randRange(_ lo: Double, _ hi: Double) -> Double {
        GenRNG.with { Double.random(in: lo...hi, using: &$0) }
    }

    static func randInt(_ lo: Int, _ hi: Int) -> Int {
        GenRNG.with { Int.random(in: lo...hi, using: &$0) }
    }

    static func randSign() -> Double {
        GenRNG.with { Bool.random(using: &$0) } ? 1.0 : -1.0
    }

    static func shuffle<T>(_ arr: [T]) -> [T] {
        GenRNG.with { arr.shuffled(using: &$0) }
    }

    static func chance(_ p: Double) -> Bool {
        GenRNG.with { Double.random(in: 0..<1, using: &$0) < p }
    }

    static func randomElement<C: Collection>(_ c: C) -> C.Element? {
        GenRNG.with { c.randomElement(using: &$0) }
    }

    static func randDouble(in range: Range<Double>) -> Double {
        GenRNG.with { Double.random(in: range, using: &$0) }
    }
}
