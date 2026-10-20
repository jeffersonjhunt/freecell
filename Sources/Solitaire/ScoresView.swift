import SolitaireEngine
import SwiftUI

/// Scores (spec "Scores"): a dark screen with a Draw 1 / Draw 3 switch, your Top 10 for that mode
/// and its two Game Center boards. A sheet on iPhone and iPad (`done` closes it), a window on the Mac.
struct ScoresView: View {
    let scores: ScoreBook
    let gameCenter: GameCenter
    var done: (() -> Void)?
    @State private var drawCount: Int
    @State private var standings: [GameCenter.Board: GameCenter.Standing] = [:]
    @State private var loaded = false

    init(scores: ScoreBook, gameCenter: GameCenter, drawCount: Int, done: (() -> Void)? = nil) {
        self.scores = scores
        self.gameCenter = gameCenter
        self.done = done
        _drawCount = State(initialValue: drawCount == 3 ? 3 : 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                titleRow
                modeSwitch
                DialogKicker(text: "YOUR TOP 10")
                topTen
                DialogKicker(text: "GAME CENTER").padding(.top, 6)
                boards
                Text("Your Top 10 syncs through iCloud to your other devices.")
                    .font(.footnote)
                    .foregroundStyle(DialogColors.label)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(DialogColors.card.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("scores")
        .task(id: drawCount) { await loadStandings() }
    }

    private var titleRow: some View {
        ZStack {
            Text("Scores")
                .font(.headline)
                .foregroundStyle(DialogColors.title)
                .accessibilityAddTraits(.isHeader)
            if let done {
                HStack {
                    Spacer()
                    Button("Done", action: done)
                        .font(.headline)
                        .foregroundStyle(DialogColors.orangeText)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach([1, 3], id: \.self) { count in
                let on = count == drawCount
                Button { drawCount = count } label: {
                    Text("DRAW \(count)")
                        .font(AppFont.mono(13, bold: true, relativeTo: .subheadline))
                        .tracking(1)
                        .foregroundStyle(on ? TableColors.onAccent : DialogColors.title)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? TableColors.accent : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Draw \(count)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x262626)))
    }

    @ViewBuilder
    private var topTen: some View {
        let list = scores.lists.list(drawCount: drawCount)
        if list.isEmpty {
            Text("No wins yet in Draw \(drawCount).")
                .font(.callout)
                .foregroundStyle(DialogColors.body)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x1E1E1E)))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                    row(index + 1, entry, last: index == list.count - 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x1E1E1E)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func row(_ rank: Int, _ entry: ScoreEntry, last: Bool) -> some View {
        let latest = scores.latest?.id == entry.id
        return HStack(spacing: 8) {
            Text("\(rank)")
                .font(AppFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(DialogColors.label)
                .frame(width: 24, alignment: .leading)
            Text(verbatim: "\(entry.score)")
                .font(AppFont.mono(17, bold: true, relativeTo: .body))
                .foregroundStyle(DialogColors.title)
                .frame(minWidth: 52, alignment: .leading)
            Text("HC")
                .font(AppFont.mono(11, bold: true, relativeTo: .caption2))
                .foregroundStyle(TableColors.onAccent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(TableColors.accent))
                .opacity(entry.hardCore ? 1 : 0)
            Spacer(minLength: 4)
            Text(GameHeader.clock(entry.elapsed))
                .font(AppFont.mono(13, relativeTo: .footnote))
                .foregroundStyle(DialogColors.body)
            Text(Self.day(entry.date))
                .font(.footnote)
                .foregroundStyle(DialogColors.label)
                .frame(minWidth: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(latest ? TableColors.accent.opacity(0.16) : .clear)
        .overlay(alignment: .bottom) { if !last { DialogColors.hairline.frame(height: 0.5) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(entry.score)\(entry.hardCore ? ", Hard Core" : ""), "
                            + "\(GameHeader.spokenClock(entry.elapsed)), \(Self.day(entry.date))")
    }

    private var boards: some View {
        VStack(spacing: 0) {
            let pair = [GameCenter.Board.of(drawCount: drawCount, hardCore: false),
                        GameCenter.Board.of(drawCount: drawCount, hardCore: true)]
            ForEach(pair, id: \.self) { board in
                Button { gameCenter.show(board) } label: {
                    HStack(spacing: 10) {
                        Text(board.title).font(.body).foregroundStyle(DialogColors.title)
                        Spacer(minLength: 8)
                        Text(standingText(board))
                            .font(AppFont.mono(13, relativeTo: .footnote))
                            .foregroundStyle(DialogColors.body)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DialogColors.label)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!gameCenter.isSignedIn)
                .overlay(alignment: .bottom) { if board == pair[0] { DialogColors.hairline.frame(height: 0.5) } }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x1E1E1E)))
    }

    private func standingText(_ board: GameCenter.Board) -> String {
        guard gameCenter.isSignedIn else { return "Not signed in" }
        guard let s = standings[board] else { return loaded ? "No score yet" : "…" }
        return "\(s.score) · #\(s.rank.formatted())"
    }

    private func loadStandings() async {
        loaded = false
        var found: [GameCenter.Board: GameCenter.Standing] = [:]
        for board in [GameCenter.Board.of(drawCount: drawCount, hardCore: false),
                      GameCenter.Board.of(drawCount: drawCount, hardCore: true)] {
            if let s = await gameCenter.standing(on: board) { found[board] = s }
        }
        standings = found
        loaded = true
    }

    /// "Today", or a short date ("Oct 1").
    static func day(_ date: Date, now: Date = .now) -> String {
        Calendar.current.isDate(date, inSameDayAs: now) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
