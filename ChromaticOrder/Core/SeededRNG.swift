//  Seeded RNG + TaskLocal threading so the generator can produce the
//  same puzzle across devices for the daily feature. Class-based so
//  the reference survives through the `RandomNumberGenerator`
//  existential and mutations persist between calls.

import Foundation

final class SeededRNGRef: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // splitmix64 hates zero seeds — remap to a non-zero constant.
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// TaskLocal RNG override. Set via `GenRNG.$current.withValue(...)` and
/// the generator's Util + direct random call sites will use it within
/// the task scope. nil = system RNG (default).
enum GenRNG {
    @TaskLocal static var current: SeededRNGRef?

    /// Execute `body` with a temporary RNG existential. Callers pass a
    /// closure that needs an inout RandomNumberGenerator — we hand them
    /// one backed by the task-local seeded ref when set, else the
    /// system generator. Class-backed existential so next() mutations
    /// persist to the shared instance inside the scope.
    static func with<T>(_ body: (inout RandomNumberGenerator) -> T) -> T {
        if let ref = current {
            var rng: RandomNumberGenerator = ref
            return body(&rng)
        }
        var rng: RandomNumberGenerator = SystemRandomNumberGenerator()
        return body(&rng)
    }
}
