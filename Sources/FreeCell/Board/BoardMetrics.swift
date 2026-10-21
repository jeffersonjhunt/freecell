import CoreGraphics

/// Every size on the board, derived from the space available. Views read from this and use no
/// numbers of their own (spec: "Layout and visuals").
struct BoardMetrics: Equatable, Sendable {
    static let columns = 8
    static let maxBoardWidth: CGFloat = 900
    static let minGap: CGFloat = 4
    static let minHitTarget: CGFloat = 44
    static let aspect: CGFloat = 1.4
    static let fanRatio: CGFloat = 0.29
    /// Phone-width boards: columns 3 pt apart inside 4 pt side margins.
    static let narrowBoardWidth: CGFloat = 500
    static let narrowGap: CGFloat = 3
    static let narrowMargin: CGFloat = 4
    /// The space between the top row (free cells, foundations) and the columns: 0.3 × card width,
    /// at most 16 pt.
    static let rowGapRatio: CGFloat = 0.3
    static let rowGapCap: CGFloat = 16
    /// The column that must always fit while staying readable: twelve cards, its fan no smaller
    /// than `readableFanRatio` (the corner index still shows). Longer columns squeeze further.
    static let readableColumn = 12
    static let readableFanRatio: CGFloat = 0.24

    let size: CGSize
    let gap: CGFloat
    /// Space between the outer columns and the board's edge.
    let margin: CGFloat
    let cardWidth: CGFloat
    /// Touch layout whose cards are narrower than the 44 pt hit target: gaps are at their minimum
    /// and each card's hit area is widened to its whole column slot.
    let isCompressed: Bool

    var cardHeight: CGFloat { cardWidth * Self.aspect }
    var cornerRadius: CGFloat { cardWidth * 0.09 }
    var fan: CGFloat { cardHeight * Self.fanRatio }
    var rowGap: CGFloat { Self.rowGap(cardWidth: cardWidth) }
    /// Width actually used by the eight columns, centred in `size.width`.
    var usedWidth: CGFloat { CGFloat(Self.columns) * cardWidth + CGFloat(Self.columns - 1) * gap }
    var leftEdge: CGFloat { (size.width - usedWidth) / 2 }
    var topRowY: CGFloat { gap }
    var tableauY: CGFloat { topRowY + cardHeight + rowGap }
    /// The tap target for one card: its whole column slot, and never under 44 pt, when compressed.
    var hitWidth: CGFloat { isCompressed ? max(cardWidth + gap, Self.minHitTarget) : cardWidth }

    init(size: CGSize, isTouch: Bool) {
        self.size = size
        let boardWidth = min(size.width, Self.maxBoardWidth)
        let narrow = boardWidth < Self.narrowBoardWidth
        var gap = narrow ? Self.narrowGap : max(boardWidth * 0.018, Self.minGap)
        var margin = narrow ? Self.narrowMargin : gap
        var width = Self.cardWidth(boardWidth: boardWidth, gap: gap, margin: margin, height: size.height)
        let compressed = isTouch && width < Self.minHitTarget
        if compressed && !narrow {
            gap = Self.minGap
            margin = Self.minGap
            width = Self.cardWidth(boardWidth: boardWidth, gap: gap, margin: margin, height: size.height)
        }
        self.gap = gap
        self.margin = margin
        self.cardWidth = max(width, 1)
        self.isCompressed = compressed
    }

    static func rowGap(cardWidth: CGFloat) -> CGFloat {
        min(cardWidth * rowGapRatio, rowGapCap)
    }

    /// The width rule, (board width − 2 margins − 7 gaps) / 8, capped by height so the top row,
    /// the row gap and a `readableColumn` fit with its fan no tighter than `readableFanRatio`
    /// (it binds only on short, wide boards: a phone held sideways, a short Mac window).
    private static func cardWidth(boardWidth: CGFloat, gap: CGFloat, margin: CGFloat, height: CGFloat) -> CGFloat {
        let columns = CGFloat(Self.columns)
        let byWidth = (boardWidth - 2 * margin - (columns - 1) * gap) / columns
        let cardsTall = 2 + CGFloat(readableColumn - 1) * readableFanRatio   // top row + last card + fans
        let room = height - 2 * gap                                          // a gap above and below
        var byHeight = room / (cardsTall + rowGapRatio / aspect) / aspect    // row gap ∝ width…
        if byHeight * rowGapRatio > rowGapCap {                              // …unless the cap binds
            byHeight = (room - rowGapCap) / cardsTall / aspect
        }
        return min(byWidth, byHeight)
    }

    func columnX(_ column: Int) -> CGFloat {
        leftEdge + CGFloat(column) * (cardWidth + gap)
    }

    /// The fan for a column of `count` cards: the spec's ratio, scaled down (never up) when the
    /// column would otherwise run past the bottom of the board.
    func fan(forColumnOf count: Int) -> CGFloat {
        let steps = CGFloat(max(count - 1, 0))
        guard steps > 0 else { return fan }
        let room = size.height - tableauY - gap - cardHeight
        return min(fan, max(room, 0) / steps)
    }
}
