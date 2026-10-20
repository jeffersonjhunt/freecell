import CoreGraphics

/// Every size on the board, derived from the space available. Views read from this and use no
/// numbers of their own (spec: "Layout and visuals").
struct BoardMetrics: Equatable, Sendable {
    static let maxBoardWidth: CGFloat = 900
    static let minGap: CGFloat = 4
    static let minHitTarget: CGFloat = 44
    static let aspect: CGFloat = 1.4
    static let faceDownFanRatio: CGFloat = 0.12
    static let faceUpFanRatio: CGFloat = 0.29
    /// Phone-width boards (decision 2026-10-01, direction A): columns 3 pt apart inside 4 pt
    /// side margins — bigger cards than the general rule's 1.8 % gaps would leave.
    static let narrowBoardWidth: CGFloat = 500
    static let narrowGap: CGFloat = 3
    static let narrowMargin: CGFloat = 4
    /// The space between the top row (stock, waste, foundations) and the columns: 0.8 × card width,
    /// at most `landscapeRowGapCap` on a touch board wider than it is tall (a device held sideways,
    /// where height is what limits the cards).
    static let rowGapRatio: CGFloat = 0.8
    static let landscapeRowGapCap: CGFloat = 16
    /// The deepest column that must always stay readable (decision D1): six face-down cards
    /// under a nine-card run (K→5), with its face-up fan no smaller than `readableFanRatio`.
    /// Fans are the steps between cards: 6 below the face-down cards, 8 between the 9 face-up.
    static let readableColumn = (faceDownCards: 6, faceUpCards: 9)
    /// A face-up fan of 0.24 × card height (0.336 × width) still shows each card's whole corner
    /// index, with a 0.07 × width margin above it (decision 2026-10-01; it was 0.2 before the
    /// index had a margin).
    static let readableFanRatio: CGFloat = 0.24

    let size: CGSize
    let gap: CGFloat
    /// Space between the outer columns and the board's edge.
    let margin: CGFloat
    let cardWidth: CGFloat
    /// Touch layout whose cards are narrower than the 44 pt hit target: gaps are at their minimum
    /// and each card's hit area is widened to its whole column slot (decision D2 in the spec).
    let isCompressed: Bool
    /// The landscape cap on the row gap, when it applies.
    let rowGapCap: CGFloat?

    var cardHeight: CGFloat { cardWidth * Self.aspect }
    var cornerRadius: CGFloat { cardWidth * 0.09 }
    var faceDownFan: CGFloat { cardHeight * Self.faceDownFanRatio }
    var faceUpFan: CGFloat { cardHeight * Self.faceUpFanRatio }
    var rowGap: CGFloat { Self.rowGap(cardWidth: cardWidth, cap: rowGapCap) }
    /// Width actually used by the seven columns, centred in `size.width`.
    var usedWidth: CGFloat { 7 * cardWidth + 6 * gap }
    var leftEdge: CGFloat { (size.width - usedWidth) / 2 }
    var topRowY: CGFloat { gap }
    var tableauY: CGFloat { topRowY + cardHeight + rowGap }
    /// The tap target for one card: its whole column slot, and never under 44 pt, when compressed.
    var hitWidth: CGFloat { isCompressed ? max(cardWidth + gap, Self.minHitTarget) : cardWidth }

    init(size: CGSize, isTouch: Bool) {
        self.size = size
        let boardWidth = min(size.width, Self.maxBoardWidth)
        let narrow = boardWidth < Self.narrowBoardWidth
        let cap: CGFloat? = isTouch && size.width > size.height ? Self.landscapeRowGapCap : nil
        var gap = narrow ? Self.narrowGap : max(boardWidth * 0.018, Self.minGap)
        var margin = narrow ? Self.narrowMargin : gap
        var width = Self.cardWidth(boardWidth: boardWidth, gap: gap, margin: margin, height: size.height, cap: cap)
        let compressed = isTouch && width < Self.minHitTarget
        if compressed && !narrow {
            gap = Self.minGap
            margin = Self.minGap
            width = Self.cardWidth(boardWidth: boardWidth, gap: gap, margin: margin, height: size.height, cap: cap)
        }
        self.gap = gap
        self.margin = margin
        self.cardWidth = max(width, 1)
        self.isCompressed = compressed
        self.rowGapCap = cap
    }

    static func rowGap(cardWidth: CGFloat, cap: CGFloat?) -> CGFloat {
        let gap = cardWidth * rowGapRatio
        return cap.map { min(gap, $0) } ?? gap
    }

    /// The width rule, (board width − 2 margins − 6 gaps) / 7, capped by height so that the top
    /// row, the row gap and the `readableColumn` fit with fans squeezed no further than
    /// `readableFanRatio` (decision D1; it only binds on short, wide boards such as a phone in
    /// landscape or a short Mac window). Exact, so the cap is never tighter than it must be.
    private static func cardWidth(boardWidth: CGFloat, gap: CGFloat, margin: CGFloat, height: CGFloat,
                                  cap: CGFloat?) -> CGFloat {
        let byWidth = (boardWidth - 2 * margin - 6 * gap) / 7
        let squeeze = readableFanRatio / faceUpFanRatio
        let downFans = CGFloat(readableColumn.faceDownCards)
        let upFans = CGFloat(readableColumn.faceUpCards - 1)
        let fans = squeeze * (downFans * faceDownFanRatio + upFans * faceUpFanRatio)
        let cardsTall = 2 + fans                                     // top row + last card + fans
        let room = height - 2 * gap                                  // a gap above and below
        // Row gap proportional to the card width…
        var byHeight = room / (cardsTall + rowGapRatio / aspect) / aspect
        // …unless the landscape cap binds at that size: then it is a fixed height.
        if let cap, byHeight * rowGapRatio > cap {
            byHeight = (room - cap) / cardsTall / aspect
        }
        return min(byWidth, byHeight)
    }

    func columnX(_ column: Int) -> CGFloat {
        leftEdge + CGFloat(column) * (cardWidth + gap)
    }

    /// Fan offsets for a column: the spec's ratios, scaled down together (never up) when the
    /// column would otherwise run past the bottom of the board.
    func fans(faceDown: Int, faceUp: Int) -> (down: CGFloat, up: CGFloat) {
        let natural = CGFloat(faceDown) * faceDownFan + CGFloat(faceUp) * faceUpFan
        guard natural > 0 else { return (faceDownFan, faceUpFan) }
        let room = size.height - tableauY - gap - cardHeight
        let scale = min(1, max(room, 0) / natural)
        return (faceDownFan * scale, faceUpFan * scale)
    }
}
