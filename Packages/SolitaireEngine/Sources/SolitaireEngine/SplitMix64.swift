/// SplitMix64: a tiny, fast, seedable generator. Used instead of `shuffled()` so a failing game
/// can be reproduced in a test from its seed alone — on every platform and Swift version.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    /// Fisher–Yates with our own index draw, so the result depends only on the seed (the
    /// standard library's `shuffle(using:)` algorithm is not guaranteed stable across versions).
    mutating func seededShuffle(using rng: inout SplitMix64) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            swapAt(i, j)
        }
    }
}
