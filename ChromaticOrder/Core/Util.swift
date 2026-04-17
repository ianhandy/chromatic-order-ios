//  Small pure helpers — Swift port of src/util.js.

import Foundation

enum Util {
    static func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T {
        min(max(x, lo), hi)
    }

    static func randRange(_ lo: Double, _ hi: Double) -> Double {
        Double.random(in: lo...hi)
    }

    static func randInt(_ lo: Int, _ hi: Int) -> Int {
        Int.random(in: lo...hi)
    }

    static func randSign() -> Double { Bool.random() ? 1.0 : -1.0 }

    static func shuffle<T>(_ arr: [T]) -> [T] { arr.shuffled() }

    static func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }
}
