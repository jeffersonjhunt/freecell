import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Solitaire

/// Spec "Win animations".
@Suite struct WinAnimationChoice {
    @Test func randomSettlesOnOneOfTheFourPerGame() {
        let picks = (0..<8).map { WinAnimation.random.resolved(seed: UInt64($0)) }
        #expect(Set(picks.compactMap { $0 }) == Set(WinAnimation.playable), "all four come up")
        #expect(WinAnimation.random.resolved(seed: 12345) == WinAnimation.random.resolved(seed: 12345), "the same each time for a game")
        #expect(!WinAnimation.playable.contains(.random) && !WinAnimation.playable.contains(.none))
    }

    @Test func noneMeansNoAnimationAndTheOthersPlayThemselves() {
        #expect(WinAnimation.none.resolved(seed: 1) == nil)
        for a in WinAnimation.playable { #expect(a.resolved(seed: 9) == a) }
    }

    @Test func anUnknownSavedChoiceIsNotAnAnimation() {
        #expect(WinAnimation(rawValue: "fireworks") == nil, "AppStorage then falls back to Cascade")
        #expect(WinAnimation.allCases.map(\.title) == ["Cascade", "Rainfall", "Decay", "Shuffle", "Random", "None"])
    }

    /// No animation (None, or Reduce Motion): the win card comes at once.
    @Test func withNoAnimationTheWinCardComesAtOnce() {
        #expect(ContentView.showsWinSheet(isWon: true, dismissed: false, cascadeFinished: false,
                                          reduceMotion: true, voiceOver: false))
    }
}

@Suite struct Rainfall {
    @Test func eachCardWaitsOnItsPileThenFallsOffTheBottom() {
        #expect(RainfallTimeline.offset(index: 3, at: 0.2, bottom: 900) == nil, "not launched yet: still on the pile")
        let early = RainfallTimeline.offset(index: 0, at: 0.2, bottom: 900)
        let later = RainfallTimeline.offset(index: 0, at: 0.6, bottom: 900)
        #expect(early != nil && later != nil && later!.dy > early!.dy, "falling, faster and faster")
        #expect(RainfallTimeline.offset(index: 0, at: 5, bottom: 900) == nil, "gone off the bottom")
        let end = RainfallTimeline.duration(total: 52, bottom: 900)
        #expect(RainfallTimeline.offset(index: 51, at: end + 0.01, bottom: 900) == nil, "all gone when it ends")
        #expect(RainfallTimeline.launched(at: 0, total: 52) == 1 && RainfallTimeline.launched(at: 100, total: 52) == 52)
    }
}

@Suite struct Decay {
    @Test func pilesDissolveTopDown() {
        #expect(DecayTimeline.progress(pile: 0, depth: 0, at: 0) == 0)
        #expect(DecayTimeline.progress(pile: 0, depth: 0, at: 0.3) > DecayTimeline.progress(pile: 0, depth: 1, at: 0.3),
                "the top card goes first")
        #expect(DecayTimeline.progress(pile: 3, depth: 0, at: 0.3) < DecayTimeline.progress(pile: 0, depth: 0, at: 0.3),
                "the piles a little apart")
        let end = DecayTimeline.duration(deepest: 13)
        for pile in 0..<4 { #expect(DecayTimeline.progress(pile: pile, depth: 12, at: end) == 1, "all gone at the end") }
    }

    /// The real shader keeps the whole card at the start, eats it away part way, and leaves
    /// nothing at the end.
    @MainActor @Test func theShaderGoesFromWholeToGone() throws {
        func opaque(_ p: Double) throws -> Double {
            let card = Rectangle().fill(.white).frame(width: 70, height: 98)
                .layerEffect(Dissolve.shader(progress: p, seed: 7, cardWidth: 70), maxSampleOffset: .zero)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            let data = try #require(image.dataProvider?.data as Data?)
            let bpp = image.bitsPerPixel / 8, row = image.bytesPerRow
            var visible = 0
            for y in 0..<image.height {
                for x in 0..<image.width where data[y * row + x * bpp + 3] > 0 { visible += 1 }
            }
            return Double(visible) / Double(image.width * image.height)
        }
        #expect(try opaque(0) == 1, "untouched")
        let half = try opaque(0.5)
        #expect(half > 0.05 && half < 0.95, "partly eaten away: \(half)")
        #expect(try opaque(1) == 0, "gone")
    }
}

@Suite struct Shuffle {
    let start = CGPoint(x: 300, y: 100), middle = CGPoint(x: 200, y: 400), stock = CGPoint(x: 30, y: 100)

    @Test func gatheredRiffledFlippedAndOnTheDrawPile() {
        let first = ShuffleTimeline.place(5, of: 52, at: 0, from: start, middle: middle, stock: stock, cardWidth: 50)
        #expect(first.center == start && first.faceUp, "starts on its foundation, face up")
        let end = ShuffleTimeline.place(5, of: 52, at: ShuffleTimeline.duration, from: start, middle: middle, stock: stock, cardWidth: 50)
        #expect(abs(end.center.x - stock.x) < 0.5 && !end.faceUp, "ends on the draw pile, face down")
        let midFlip = ShuffleTimeline.gather + ShuffleTimeline.riffle + ShuffleTimeline.flip / 2
        #expect(ShuffleTimeline.place(5, of: 52, at: midFlip, from: start, middle: middle, stock: stock, cardWidth: 50).squeeze < 0.1,
                "edge-on halfway through the flip")
    }
}

@Suite struct AnimationClockTests {
    /// The first frame starts the clock; later frames measure from it.
    @Test func startsOnTheFirstFrame() {
        let clock = AnimationClock()
        let t0 = Date(timeIntervalSince1970: 1000)
        #expect(clock.elapsed(at: t0) == 0)
        #expect(clock.elapsed(at: t0.addingTimeInterval(2.5)) == 2.5)
    }
}
