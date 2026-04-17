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
    @State private var name: String = ""
    @State private var showHelp: Bool = false
    @State private var didLoadEditing: Bool = false

    @Bindable var game: GameState
    /// When true, the Play button also writes the puzzle to the
    /// gallery before loading it. Set by callers coming from the
    /// Gallery view; the top-level menu's "Create Puzzle…" entry
    /// leaves it false (one-off play, not a keep-forever save).
    var saveOnPlay: Bool = false
    /// Non-nil when opened from a gallery row's "Edit" action. On
    /// appear we rehydrate `state` from its doc; Save overwrites this
    /// entry instead of creating a new one.
    var editing: GalleryPuzzle? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                nameField
                colorBar
                toolPicker
                CanvasView(state: state)
                    .padding(.horizontal, 14)
                toolBar
            }
            .padding(.vertical, 10)
            .navigationTitle(editing == nil ? "Create" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .onAppear {
                if !didLoadEditing, let e = editing {
                    CreatorCodec.populate(state, from: e.doc)
                    name = e.doc.name ?? ""
                    didLoadEditing = true
                }
            }
            .sheet(isPresented: $showHelp) {
                CreatorHelpSheet()
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
                    deltaL: $state.deltaL,
                    deltaC: $state.deltaC,
                    deltaH: $state.deltaH,
                    title: "End color"
                )
            }
        }
    }

    private func syncEndToggle() {
        endDisabled = state.endColor == nil
    }

    /// Write-back helper for the Play button. When editing, overwrite
    /// the original gallery entry with the current layout + name.
    /// When creating + saveOnPlay, save a new entry. Otherwise no-op
    /// (one-off play from the main-menu "Create Puzzle" path).
    private func persistIfNeeded(puzzle: Puzzle, difficulty: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenName: String? = trimmed.isEmpty ? nil : trimmed
        if let editing {
            let json = (try? CreatorCodec.encodePuzzle(puzzle)) ?? ""
            guard let data = json.data(using: .utf8),
                  var doc = try? CreatorCodec.decode(data) else { return }
            doc.name = chosenName
            doc.difficulty = difficulty
            try? GalleryStore.overwrite(editing, with: doc)
        } else if saveOnPlay {
            _ = try? GalleryStore.saveNamed(puzzle, name: chosenName)
        }
    }

    // ─── Name field ─────────────────────────────────────────────────

    private var nameField: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Untitled puzzle", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .submitLabel(.done)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    // ─── Tool picker ────────────────────────────────────────────────

    private var toolPicker: some View {
        HStack(spacing: 8) {
            toolButton(.paint, system: "paintbrush.fill", label: "Paint")
            toolButton(.erase, system: "eraser.fill", label: "Erase")
            toolButton(.eyedropper, system: "eyedropper", label: "Pick")
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func toolButton(_ t: CreatorState.Tool, system: String, label: String) -> some View {
        let selected = state.tool == t
        Button {
            state.tool = t
            state.cancelDrag()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.white : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

                // Share: attaches a .json file (KromaPuzzleFile) so the
                // recipient gets a real file attachment — save to
                // Files, preview in Mail, forward via AirDrop — instead
                // of a wall of text pasted into the message body. The
                // App Store link rides in the `message` slot so
                // non-installers still get pointed to the app.
                if let b = built,
                   let json = try? CreatorCodec.encodeString(
                        state,
                        difficulty: b.validation.difficulty) {
                    let file = KromaPuzzleFile(
                        json: json,
                        difficulty: b.validation.difficulty
                    )
                    ShareLink(
                        item: file,
                        subject: Text("A Kroma puzzle"),
                        message: Text("difficulty \(b.validation.difficulty)/10 — https://apps.apple.com/app/kroma"),
                        preview: SharePreview(
                            "Kroma puzzle (\(b.validation.difficulty)/10)",
                            image: Image(systemName: "paintpalette.fill")
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
                        persistIfNeeded(puzzle: b.puzzle, difficulty: b.validation.difficulty)
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
            } else {
                Text("Tap a painted cell to reveal it at the start")
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

            // Total grid dimensions with cell spacing baked in — used
            // both for laying out the tiles and for drawing the outer
            // bounds outline right at the edge of the playable area.
            let totalW = CGFloat(cols) * (cellPx + spacing * 2)
            let totalH = CGFloat(rows) * (cellPx + spacing * 2)
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
                                    isConflict: state.dragInvalid && preview[idx] != nil,
                                    isLocked: state.manualLocks.contains(idx)
                                )
                                .frame(width: cellPx + spacing * 2,
                                       height: cellPx + spacing * 2)
                            }
                        }
                    }
                }
                .frame(width: totalW, height: totalH)
                .background(
                    // Outer-bounds outline around the whole canvas —
                    // the playfield edges get ambiguous otherwise
                    // because empty-cell tints are low-contrast on
                    // black. White stroke for visibility against the
                    // dark theme (the previous black-on-black stroke
                    // was effectively invisible).
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.28),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .padding(-4)
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in
                        let hit = state.cellFrames.first(where: {
                            $0.value.contains(v.location)
                        })?.key
                        switch state.tool {
                        case .paint:
                            if state.dragStart == nil {
                                if let hit { state.beginDrag(at: hit) }
                            } else {
                                state.updateDrag(to: v.location)
                            }
                        case .erase:
                            if let hit { state.eraseHits.insert(hit) }
                        case .eyedropper:
                            if let hit { state.pickColor(at: hit) }
                        }
                    }
                    .onEnded { _ in
                        switch state.tool {
                        case .paint:
                            // A gesture that never moved (dragAxis
                            // never locked) is treated as a tap. On a
                            // committed cell, tap toggles the
                            // revealed-at-start lock; on an empty cell
                            // it's a no-op. Anything with a locked
                            // axis is a drag and goes to commit.
                            if state.dragAxis == nil,
                               let start = state.dragStart,
                               state.committedCells[start] != nil {
                                state.toggleLock(at: start)
                                state.cancelDrag()
                            } else {
                                _ = state.commitDrag()
                            }
                        case .erase:
                            state.erase(cells: state.eraseHits)
                            state.eraseHits.removeAll()
                        case .eyedropper:
                            break
                        }
                    }
            )
            .onPreferenceChange(CanvasCellFramesKey.self) { frames in
                Task { @MainActor in state.cellFrames = frames }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─── Help sheet ──────────────────────────────────────────────────────

struct CreatorHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(
                        icon: "paintbrush.fill",
                        title: "Paint mode",
                        body: """
                        Tap the Start chip to pick a color.
                        Tap the End chip to pick an end color — or switch to Shift \
                        mode and dial Δh / ΔL / Δc for a stepped gradient.

                        Drag across the canvas to lay the gradient. The preview \
                        snaps to horizontal or vertical.

                        Tap an empty cell next to an existing gradient to extend \
                        it by one — continue dragging to keep extending. Tap a \
                        painted cell to mark it as a starter clue (or clear it).
                        """
                    )
                    section(
                        icon: "eraser.fill",
                        title: "Erase mode",
                        body: """
                        Tap or drag across painted cells to remove the gradient(s) \
                        they belong to. Erase works on whole gradients — not \
                        single cells.
                        """
                    )
                    section(
                        icon: "eyedropper",
                        title: "Pick mode",
                        body: """
                        Tap any painted cell to copy its color into the Start \
                        chip. Drag to scrub — the Start color updates live as \
                        your finger moves.
                        """
                    )
                    section(
                        icon: "square.grid.3x3",
                        title: "Intersections",
                        body: """
                        Where two gradients cross, the shared cell belongs to \
                        both. Intersections are auto-locked as starter clues so \
                        the puzzle has a unique solution.
                        """
                    )
                    section(
                        icon: "checkmark.seal.fill",
                        title: "Ready to play",
                        body: """
                        Lay at least one gradient with at least one free cell. \
                        The validation banner flags any issues (no clues, \
                        repeated colors, direction ambiguity). Press Play when \
                        it's green.
                        """
                    )
                }
                .padding(20)
            }
            .navigationTitle("How to create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CreatorCell: View {
    let idx: CellIndex
    let cellPx: CGFloat
    let radius: CGFloat
    let committed: OKLCh?
    let preview: OKLCh?
    let isConflict: Bool
    let isLocked: Bool

    var body: some View {
        ZStack {
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
            if isConflict {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color(red: 0.9, green: 0.2, blue: 0.2), lineWidth: 2)
                    .frame(width: cellPx, height: cellPx)
            }
            // Manual-lock badge — small white dot in the corner,
            // mirrors the play-mode "this is a starter cell" style.
            if isLocked, let c = committed {
                let L = c.L
                let dotColor: Color = L > 0.55
                    ? Color.black.opacity(0.38)
                    : Color.white.opacity(0.78)
                Circle()
                    .fill(dotColor)
                    .frame(width: cellPx * 0.18, height: cellPx * 0.18)
                    .frame(width: cellPx, height: cellPx, alignment: .bottomTrailing)
                    .padding(cellPx * 0.14)
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
