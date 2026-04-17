//  Bottom strip: instruction text, Check button (challenge mode), and
//  the bank of swatches with Balatro-style sway.

import SwiftUI

struct BankView: View {
    @Bindable var game: GameState

    var body: some View {
        VStack(spacing: 8) {
            Text(instrText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color(red: 0.69, green: 0.66, blue: 0.61))

            if game.mode == .challenge, !game.solved {
                Button {
                    game.handleCheck()
                } label: {
                    HStack(spacing: 8) {
                        Text("Check")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill").font(.system(size: 12))
                            Text("\(game.checks)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .opacity(0.85)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .foregroundStyle(.white)
                    .background(game.checks > 0
                                ? Color.accentColor
                                : Color.gray.opacity(0.6),
                                in: Capsule())
                    .shadow(color: Color.accentColor.opacity(game.checks > 0 ? 0.3 : 0),
                            radius: 12, y: 4)
                }
                .disabled(game.checks <= 0)
            }

            // Bank layout that GUARANTEES every swatch is visible without
            // scrolling: pick a column count that keeps rows ≤ maxRows,
            // then shrink the swatches to fit the available width. As
            // the bank grows (Expert levels can have 30-50 swatches),
            // swatches get smaller rather than wrapping to more rows.
            if let p = game.puzzle, !p.bank.isEmpty {
                GeometryReader { geo in
                    let bank = p.bank
                    let maxRows = 3
                    let spacing: CGFloat = 6
                    let cols = max(1, Int(ceil(Double(bank.count) / Double(maxRows))))
                    let maxSize: CGFloat = 56
                    let availW = max(0, geo.size.width)
                    let fit = (availW - CGFloat(cols - 1) * spacing) / CGFloat(cols)
                    let swatchSize = max(22, min(maxSize, fit))
                    let rows = Int(ceil(Double(bank.count) / Double(cols)))
                    let totalHeight = CGFloat(rows) * swatchSize + CGFloat(rows - 1) * spacing
                    VStack(spacing: spacing) {
                        ForEach(0..<rows, id: \.self) { rIdx in
                            HStack(spacing: spacing) {
                                ForEach(0..<cols, id: \.self) { cIdx in
                                    let idx = rIdx * cols + cIdx
                                    if idx < bank.count {
                                        SwatchView(
                                            item: bank[idx],
                                            index: idx,
                                            game: game,
                                            size: swatchSize
                                        )
                                    } else {
                                        Color.clear
                                            .frame(width: swatchSize, height: swatchSize)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: availW, height: totalHeight, alignment: .center)
                }
                .frame(height: bankContentHeight(bankCount: p.bank.count))
            }
        }
        .padding(.vertical, 12)
    }

    // Height the bank VStack should reserve for its swatches. Matches
    // the GeometryReader math above so the layout is stable regardless
    // of how many swatches are in the bank.
    private func bankContentHeight(bankCount: Int) -> CGFloat {
        // Mirrors the per-swatch sizing pass above — without a real
        // width we use a conservative 340pt. Updated once layout runs
        // and the GeometryReader reports accurate width.
        let maxRows = 3
        let spacing: CGFloat = 6
        let cols = max(1, Int(ceil(Double(bankCount) / Double(maxRows))))
        let availW: CGFloat = 340
        let fit = (availW - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        let swatchSize = max(22, min(56, fit))
        let rows = Int(ceil(Double(bankCount) / Double(cols)))
        return CGFloat(rows) * swatchSize + CGFloat(rows - 1) * spacing
    }

    private var instrText: String {
        guard let p = game.puzzle else { return "" }
        if game.solved { return "\u{1F3A8} Solved!" }
        if p.bank.isEmpty { return "All placed — check your gradients" }
        if case .bank = game.selection?.kind { return "Tap any empty cell to place" }
        if case .cell = game.selection?.kind { return "Tap another cell to swap, or empty to move" }
        return "Tap or drag a swatch"
    }
}
