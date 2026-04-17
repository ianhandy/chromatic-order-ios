//  Puzzle creator. Top row: two OKLCh color swatches (start + end) +
//  Δ readout. Center: the canvas. Bottom: tools (Undo, Clear,
//  Export / Share, Play this, validation banner).
//
//  Drag the canvas from one cell to another to lay a gradient. The
//  gesture snaps to horizontal / vertical on the second cell, shows
//  a ghost fill along the way, and commits on release (or rejects
//  on intersection conflict — see CreatorState.previewConflicts).

import SwiftUI

struct CanvasCellFramesKey: PreferenceKey {
    static var defaultValue: [CellIndex: CGRect] = [:]
    static func reduce(value: inout [CellIndex: CGRect], nextValue: () -> [CellIndex: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CreatorView: View {
    @State private var state = CreatorState()
    @State private var pickingStart = false
    @State private var pickingEnd = false
    /// Controls whether the End chip currently means "no end color"
    /// (shift mode). Bound to state.endColor == nil via a two-way
    /// intermediary so the sheet toggle reads/writes naturally.
    @State private var endDisabled = false

    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                colorBar
                CanvasView(state: state)
                    .padding(.horizontal, 14)
                toolBar
            }
            .padding(.vertical, 10)
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $pickingStart) {
                ColorPickerSheet(color: $state.startColor, title: "Start color")
            }
            .sheet(isPresented: $pickingEnd, onDismiss: syncEndToggle) {
                ColorPickerSheet(
                    color: Binding(
                        get: { state.endColor ?? state.startColor },
                        set: { state.endColor = $0 }
                    ),
                    isNilled: Binding(
                        get: { endDisabled },
                        set: { newVal in
                            endDisabled = newVal
                            state.endColor = newVal ? nil : (state.endColor ?? state.startColor)
                        }
                    ),
                    title: "End color"
                )
            }
        }
    }

    private func syncEndToggle() {
        endDisabled = state.endColor == nil
    }

    // ─── Top: color swatches + Δ readout ────────────────────────────

    private var colorBar: some View {
        HStack(spacing: 12) {
            ColorChip(color: state.startColor, label: "Start") { pickingStart = true }

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            // End chip shows striped placeholder when shift-mode is on.
            if let end = state.endColor {
                ColorChip(color: end, label: "End") { pickingEnd = true }
            } else {
                ShiftChip(deltaL: state.deltaL, deltaC: state.deltaC, deltaH: state.deltaH) {
                    pickingEnd = true
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // ─── Bottom: tools + validation ─────────────────────────────────

    /// Live-computed puzzle + validation. `nil` until at least one
    /// gradient is laid. Recomputed on every render — cheap enough.
    private var built: (puzzle: Puzzle, validation: CreatorValidation)? {
        CreatorBuilder.build(from: state)
    }

    private var toolBar: some View {
        VStack(spacing: 8) {
            validationBanner

            HStack(spacing: 10) {
                Button {
                    state.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(state.gradients.isEmpty)

                Button(role: .destructive) {
                    state.clearAll()
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(height: 36)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .disabled(state.gradients.isEmpty)

                Spacer()

                // Share: builds an export string + intro + link on the
                // fly. ShareLink handles the system sheet natively.
                if let b = built {
                    ShareLink(
                        item: shareText(for: b),
                        subject: Text("A puzzle from Chromatic Order"),
                        message: Text("Try this puzzle I made!"),
                        preview: SharePreview(
                            "Puzzle · difficulty \(b.validation.difficulty)"
                        )
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {} label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }

                Button {
                    if let b = built, b.validation.playable {
                        game.loadCustomPuzzle(b.puzzle)
                        dismiss()
                    }
                } label: {
                    Text("Play")
                        .font(.system(size: 13, weight: .bold))
                        .frame(height: 36)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(built?.validation.playable ?? false))
            }
            .padding(.horizontal, 14)

            if state.gradients.isEmpty {
                Text("Tap a color, drag across the canvas to lay a gradient")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
        }
    }

    // Info + warning banner — shows the live difficulty and any issues
    // the builder flagged. Warnings render in red; stat text is neutral.
    @ViewBuilder
    private var validationBanner: some View {
        if let b = built {
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    Label("\(b.validation.difficulty)/10", systemImage: "gauge")
                        .font(.system(size: 11, weight: .semibold))
                    Label("\(b.validation.gradientCount) grads", systemImage: "line.diagonal")
                        .font(.system(size: 11, weight: .semibold))
                    Label("\(b.validation.bankCount) free", systemImage: "square.grid.2x2")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                ForEach(b.validation.warnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(w).font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Color(red: 0.85, green: 0.35, blue: 0.1))
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// Text payload for the Share sheet. Contains a short intro + the
    /// JSON doc + the App Store link so recipients without the app get
    /// pointed to the install page.
    private func shareText(for b: (puzzle: Puzzle, validation: CreatorValidation)) -> String {
        let json = (try? CreatorCodec.encodeString(state, difficulty: b.validation.difficulty)) ?? ""
        let appStore = "https://apps.apple.com/app/chromatic-order"
        return """
        I made a puzzle in Chromatic Order — difficulty \(b.validation.difficulty)/10.

        \(json)

        Don't have the app? \(appStore)
        """
    }
}

// ─── Color chips ─────────────────────────────────────────────────────

private struct ColorChip: View {
    let color: OKLCh
    let label: String
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OK.toColor(color))
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.trailing, 6)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ShiftChip: View {
    let deltaL: Double
    let deltaC: Double
    let deltaH: Double
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Shift")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(format: "Δh %.0f°", deltaH))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 8)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// ─── Canvas ──────────────────────────────────────────────────────────

private struct CanvasView: View {
    @Bindable var state: CreatorState

    var body: some View {
        GeometryReader { geo in
            let cols = CreatorState.canvasCols
            let rows = CreatorState.canvasRows
            let spacing: CGFloat = 2
            let availW = geo.size.width
            let availH = geo.size.height
            let cellW = (availW - CGFloat(cols) * spacing * 2) / CGFloat(cols)
            let cellH = (availH - CGFloat(rows) * spacing * 2) / CGFloat(rows)
            let cellPx = max(18, min(cellW, cellH, 44))
            let committed = state.committedCells
            let preview = Dictionary(uniqueKeysWithValues:
                state.previewCells().map { ($0.idx, $0.color) })
            let radius = cellPx * 0.22

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<cols, id: \.self) { c in
                                let idx = CellIndex(r: r, c: c)
                                CreatorCell(
                                    idx: idx,
                                    cellPx: cellPx,
                                    radius: radius,
                                    committed: committed[idx],
                                    preview: preview[idx],
                                    isConflict: state.dragInvalid && preview[idx] != nil
                                )
                                .frame(width: cellPx + spacing * 2,
                                       height: cellPx + spacing * 2)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in
                        if state.dragStart == nil {
                            // First touch — hit-test the start cell.
                            if let hit = state.cellFrames.first(where: {
                                $0.value.contains(v.location)
                            })?.key {
                                state.beginDrag(at: hit)
                            }
                        } else {
                            state.updateDrag(to: v.location)
                        }
                    }
                    .onEnded { _ in
                        _ = state.commitDrag()
                    }
            )
            .onPreferenceChange(CanvasCellFramesKey.self) { frames in
                Task { @MainActor in state.cellFrames = frames }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CreatorCell: View {
    let idx: CellIndex
    let cellPx: CGFloat
    let radius: CGFloat
    let committed: OKLCh?
    let preview: OKLCh?
    let isConflict: Bool

    var body: some View {
        ZStack {
            // Base tile — gray-tint "empty slot" look when nothing lives
            // here yet, matching the bank's vacant-slot styling.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(committed == nil && preview == nil ? 0.04 : 0))
                .frame(width: cellPx, height: cellPx)

            if let c = committed {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OK.toColor(c))
                    .frame(width: cellPx, height: cellPx)
            }
            if let p = preview {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OK.toColor(p, opacity: 0.85))
                    .frame(width: cellPx, height: cellPx)
            }
            // Red tint on conflict so the player sees immediately why
            // the commit won't land.
            if isConflict {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color(red: 0.9, green: 0.2, blue: 0.2), lineWidth: 2)
                    .frame(width: cellPx, height: cellPx)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CanvasCellFramesKey.self,
                    value: [idx: geo.frame(in: .global)]
                )
            }
        )
    }
}
