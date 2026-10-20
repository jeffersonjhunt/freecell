import CoreGraphics
import Foundation
import SolitaireEngine

/// macOS double-click is "the same as a tap" (spec). A double-click is two clicks, and the first
/// already moved the card, so the second would land on whatever it uncovered and move that too.
/// This drops any click that follows the previous one within the double-click interval, near the
/// same point — so a double-click (or a triple-click) acts exactly once. It is for card moves only;
/// the stock must count every click.
struct ClickFilter {
    let interval: TimeInterval
    let slop: CGFloat
    private var last: (time: Date, point: CGPoint)?

    init(interval: TimeInterval, slop: CGFloat = 6) {
        self.interval = interval
        self.slop = slop
    }

    /// Whether a click at `point` should act. Every click, acted on or not, restarts the window,
    /// so a rapid run of clicks in one place acts once.
    mutating func accept(at point: CGPoint, time: Date = Date()) -> Bool {
        defer { last = (time, point) }
        if let last, time.timeIntervalSince(last.time) < interval,
           abs(point.x - last.point.x) <= slop, abs(point.y - last.point.y) <= slop {
            return false                            // a follow-up click of a multi-click: swallowed
        }
        return true
    }
}

/// Decides what a tap or click does before the store sees it: a click on the stock always draws
/// (every click counts, however fast); a click on a card is a move, unless it is a follow-up click
/// of a macOS double- or triple-click, which is ignored. Accessibility actions (no point) always act.
struct TapRouter {
    enum Action: Equatable { case draw, move, ignore }

    var clicks: ClickFilter
    /// macOS only: iOS has no double-click, so every tap acts.
    let filtersRepeatClicks: Bool

    mutating func route(_ pile: PileID, at point: CGPoint?, time: Date = Date()) -> Action {
        if case .stock = pile { return .draw }
        guard filtersRepeatClicks, let point else { return .move }
        return clicks.accept(at: point, time: time) ? .move : .ignore
    }
}
