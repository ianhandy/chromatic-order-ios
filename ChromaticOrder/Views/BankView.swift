//  Bottom strip: instruction text, Check button (challenge mode), and
//  the bank of swatches. The bank is a fixed-size grid of drop-
//  targetable slots — slots are empty when their swatch has been
//  placed on the board, and they accept swatches back (drag-off-grid
//  fallback, or explicit drag into a slot). Swatches can also be
//  rearranged between slots.

import SwiftUI

struct BankSlotFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

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

            // Fixed toolbox layout. Column count + swatch size come from
            // the puzzle's initialBankCount, not the live bank contents —
            // placed swatches leave their slot empty; the grid shape
            // stays constant so the player can drop a returned swatch
            // into whichever slot they want.
            if let p = game.puzzle, p.initialBankCount > 0 {
                GeometryReader { geo in
                    let initial = p.initialBankCount
                    let maxRows = 3
                    let spacing: CGFloat = 6
                    let cols = max(1, Int(ceil(Double(initial) / Double(maxRows))))
                    let maxSize: CGFloat = 56
                    let availW = max(0, geo.size.width)
                    let fit = (availW - CGFloat(cols - 1) * spacing) / CGFloat(cols)
                    let swatchSize = max(22, min(maxSize, fit))
                    let rows = Int(ceil(Double(initial) / Double(cols)))
                    let totalHeight = CGFloat(rows) * swatchSize + CGFloat(rows - 1) * spacing
                    VStack(spacing: spacing) {
                        ForEach(0..<rows, id: \.self) { rIdx in
                            HStack(spacing: spacing) {
                                ForEach(0..<cols, id: \.self) { cIdx in
                                    let slot = rIdx * cols + cIdx
                                    if slot < p.bank.count {
                                        BankSlotView(
                                            slot: slot,
                                            size: swatchSize,
                                            game: game
                                        )
                                    } else {
                                        // Pad when cols×rows overflows the
                                        // logical slot count.
                                        Color.clear
                                            .frame(width: swatchSize, height: swatchSize)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: availW, height: totalHeight, alignment: .top)
                }
                .frame(height: bankContentHeight(initialBankCount: p.initialBankCount))
                .onPreferenceChange(BankSlotFramesKey.self) { frames in
                    Task { @MainActor in game.bankSlotFrames = frames }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func bankContentHeight(initialBankCount: Int) -> CGFloat {
        let maxRows = 3
        let spacing: CGFloat = 6
        let cols = max(1, Int(ceil(Double(initialBankCount) / Double(maxRows))))
        let availW: CGFloat = 340
        let fit = (availW - CGFloat(cols - 1) * spacing) / CGFloat(cols)
        let swatchSize = max(22, min(56, fit))
        let rows = Int(ceil(Double(initialBankCount) / Double(cols)))
        return CGFloat(rows) * swatchSize + CGFloat(rows - 1) * spacing
    }

    private var instrText: String {
        guard let p = game.puzzle else { return "" }
        if game.solved { return "\u{1F3A8} Solved!" }
        if p.bank.allSatisfy({ $0 == nil }) { return "All placed — check your gradients" }
        if case .bank = game.selection?.kind { return "Tap a cell or slot to place" }
        if case .cell = game.selection?.kind { return "Tap another cell, empty cell, or slot" }
        return "Tap or drag a swatch"
    }
}
