//  Puzzle creator. Top row: two OKLCh color swatches (start + end) +
//  Δ readout. Center: the canvas. Bottom: tools (Undo, Clear,
//  Export / Share, Play this, validation banner).
//
//  Drag the canvas from one cell to another to lay a gradient. The
//  gesture snaps to horizontal / vertical on the second cell, shows
//  a ghost fill along the way, and commits on release (or rejects
//  on intersection conflict — see CreatorState.previewConflicts).

import SwiftUI

/// UI state for CreatorView's community Submit button. Tracks the
/// network roundtrip and the post-roundtrip outcome so the bottom
/// bar can render a matching inline status row without needing a
/// sheet or alert.
enum CommunitySubmitState {
    case idle
    case submitting
    case success(String)     // "pending" | "approved" | "rejected"
    case failed(String)

    var isInFlight: Bool {
        if case .submitting = self { return true }
        return false
    }
}

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
    @State private var showExitConfirm: Bool = false
    /// Tracks whether the name TextField currently owns focus. Used
    /// to collapse the bottom tool bar + validation banner while the
    /// keyboard is up — the player is mid-type, they don't need a
    /// Save / Share / Undo row in their face (and it gives the
    /// keyboard uncluttered whitespace to cover).
    @FocusState private var nameFocused: Bool

    /// Drives the Submit-to-community button's UI state: idle, in
    /// flight, or displaying the result of the most recent attempt.
    @State private var submitState: CommunitySubmitState = .idle

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
    /// When set, new saves (saveOnPlay) land inside this collection
    /// rather than at the gallery root. Ignored when `editing` is
    /// non-nil — editing overwrites the original file in place.
    var collection: GalleryCollection? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                nameField
                headerBar
                CanvasView(state: state)
                    .padding(.horizontal, 14)
                if !nameFocused {
                    toolBar
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.25), value: nameFocused)
            .navigationTitle(editing == nil ? "Create" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        // Protect against accidental taps on the
                        // Close button after the player has started
                        // building. Empty creator = no prompt;
                        // anything laid down = confirm first.
                        if state.gradients.isEmpty {
                            dismiss()
                        } else {
                            showExitConfirm = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Overflow menu — collects secondary actions that
                    // used to clutter the bottom action row. Submit
                    // lives here so it has room to breathe and the
                    // bottom row stays focused on Undo / Clear /
                    // Share / Save.
                    Menu {
                        Button {
                            submitBuiltToCommunity()
                        } label: {
                            if case .submitting = submitState {
                                Label("Submitting…", systemImage: "paperplane.fill")
                            } else {
                                Label("Submit to Community", systemImage: "paperplane.fill")
                            }
                        }
                        .disabled(!(built?.validation.playable ?? false) || submitState.isInFlight)

                        Divider()

                        Button {
                            showHelp = true
                        } label: {
                            Label("Help", systemImage: "questionmark.circle")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
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
            .confirmationDialog(
                "Exit without saving?",
                isPresented: $showExitConfirm,
                titleVisibility: .visible
            ) {
                Button("Exit without saving", role: .destructive) {
                    dismiss()
                }
                Button("Keep building", role: .cancel) { }
            } message: {
                Text("Your puzzle won't be saved. Tap Play to save it first.")
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

    /// Build a `kroma://play?data=<base64url>` link that embeds the
    /// puzzle JSON inline. Tapping the URL opens the app's onOpenURL
    /// handler and lands the player in the puzzle immediately — no
    /// file attachment dance.
    private func kromaPlayURL(json: String) -> URL {
        let data = Data(json.utf8)
        let payload = ChromaticOrderApp.encodeBase64URL(data)
        return URL(string: "kroma://play?data=\(payload)")!
    }

    // ─── Bottom-bar atoms ───────────────────────────────────────────

    private enum BottomButtonTone { case neutral, destructive, prominent }

    /// Shared styling for the bottom action bar so every button has
    /// the same height, icon + label stack, and touch target. Tone
    /// picks the color treatment without forcing three different
    /// button-style calls at each call-site.
    private func bottomBarForegroundColor(disabled: Bool, tone: BottomButtonTone) -> Color {
        if disabled { return Color.white.opacity(0.3) }
        switch tone {
        case .prominent: return Color.black
        case .destructive: return Color(red: 0.92, green: 0.42, blue: 0.42)
        case .neutral: return Color.white.opacity(0.9)
        }
    }

    private func bottomBarFillColor(disabled: Bool, tone: BottomButtonTone) -> Color {
        if disabled { return Color.white.opacity(0.04) }
        if tone == .prominent { return Color.white }
        return Color.white.opacity(0.08)
    }

    private func bottomBarStrokeColor(disabled: Bool, tone: BottomButtonTone) -> Color {
        if disabled { return Color.white.opacity(0.08) }
        if tone == .prominent { return Color.clear }
        return Color.white.opacity(0.2)
    }

    @ViewBuilder
    private func bottomBarButton(
        system: String,
        label: String,
        disabled: Bool,
        tone: BottomButtonTone,
        action: @escaping () -> Void
    ) -> some View {
        let fg = bottomBarForegroundColor(disabled: disabled, tone: tone)
        let fill = bottomBarFillColor(disabled: disabled, tone: tone)
        let stroke = bottomBarStrokeColor(disabled: disabled, tone: tone)
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(fg)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Share is special — it wraps SwiftUI's ShareLink around a
    /// KromaPuzzleFile so the system share sheet handles the AirDrop
    /// / Messages / Mail routing. Rendered to match bottomBarButton
    /// so the row stays visually uniform.
    @ViewBuilder
    private var shareBottomButton: some View {
        let playable = built?.validation.playable ?? false
        if playable, let b = built,
           let json = try? CreatorCodec.encodeString(
               state, difficulty: b.validation.difficulty) {
            let file = KromaPuzzleFile(
                json: json,
                difficulty: b.validation.difficulty
            )
            let shareURL = kromaPlayURL(json: json)
            let previewImage = PuzzlePreviewRenderer.render(b.puzzle)
            ShareLink(
                item: file,
                subject: Text("A Kromatika puzzle"),
                message: Text("difficulty \(b.validation.difficulty)/10 — tap to play: \(shareURL)"),
                preview: SharePreview(
                    "Kromatika puzzle (\(b.validation.difficulty)/10)",
                    image: previewImage ?? Image(systemName: "paintpalette.fill")
                )
            ) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Share")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Color.white.opacity(0.9))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        } else {
            bottomBarButton(
                system: "square.and.arrow.up",
                label: "Share",
                disabled: true,
                tone: .neutral
            ) { /* no-op; disabled */ }
        }
    }

    // ─── Community submit ───────────────────────────────────────────

    /// Renders the current submit-state as a small single-line row
    /// under the action bar. Collapses to zero height when idle so
    /// it doesn't permanently reserve vertical space.
    @ViewBuilder
    private var submitStatusRow: some View {
        switch submitState {
        case .idle:
            EmptyView()
        case .submitting:
            Text("Submitting…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
        case .success(let status):
            let label: String = {
                switch status {
                case "pending":  return "Submitted — awaiting review."
                case "approved": return "Already approved — it's in the community pool."
                case "rejected": return "This puzzle was previously rejected."
                default:         return "Submitted."
                }
            }()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 14)
        case .failed(let message):
            Text("Submit failed: \(message)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
        }
    }

    /// Build the current doc, fire the submit request, surface the
    /// result through `submitState`. The server dedups by content
    /// hash so repeatedly tapping Submit on the same layout echoes
    /// back the existing row's status rather than queuing dupes.
    private func submitBuiltToCommunity() {
        guard case .idle = submitState else { return }
        guard let b = built, b.validation.playable else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let submitterName = trimmedName.isEmpty ? nil : trimmedName
        let difficulty = b.validation.difficulty
        let puzzle = b.puzzle
        // Encode on the main actor (CreatorState is MainActor-bound),
        // then fire the request off-actor.
        let level = puzzle.level
        guard let json = try? CreatorCodec.encodeString(
                state, difficulty: difficulty, name: submitterName),
              let data = json.data(using: .utf8),
              let doc = try? CreatorCodec.decode(data) else {
            submitState = .failed("couldn't encode puzzle")
            return
        }
        submitState = .submitting
        Task {
            let result = await CommunityStore.submit(
                doc: doc, level: level, submitterName: submitterName
            )
            await MainActor.run {
                switch result {
                case .success(let resp):
                    submitState = .success(resp.status ?? "pending")
                case .failure(let err):
                    submitState = .failed(err.localizedDescription)
                }
            }
        }
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
            if (try? GalleryStore.saveNamed(puzzle, name: chosenName, in: collection)) != nil {
                GameCenter.shared.reportAchievement(
                    GameCenter.Achievement.createdLevel
                )
            }
        }
    }

    // ─── Name field ─────────────────────────────────────────────────

    private var nameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Untitled puzzle", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .semibold))
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { nameFocused = false }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    // ─── Tool picker ────────────────────────────────────────────────

    // ─── Top header: colors (left) + tools (right), no labels ─────────

    /// Single row above the canvas. Colors live on the left (start
    /// swatch + arrow + end swatch / shift preview), tools live on
    /// the right as icon-only chips. Text labels removed in favor
    /// of larger touch targets — the icons carry meaning and the
    /// selected tool state is picked up via the filled background.
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 14) {
            colorCluster
            Spacer(minLength: 8)
            toolCluster
        }
        .padding(.horizontal, 14)
    }

    /// Start swatch + arrow + end swatch (or shift-preview strip).
    /// Chips are ~50pt tall, the arrow is bold and 22pt so it
    /// anchors the left side visually.
    private var colorCluster: some View {
        HStack(spacing: 10) {
            ColorChip(color: state.startColor) { pickingStart = true }

            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.65))

            if let end = state.endColor {
                ColorChip(color: end) { pickingEnd = true }
            } else {
                ShiftChip(
                    startColor: state.startColor,
                    deltaL: state.deltaL,
                    deltaC: state.deltaC,
                    deltaH: state.deltaH
                ) { pickingEnd = true }
            }
        }
    }

    /// Three icon-only tool buttons. Touch target ~44x44; the
    /// selected tool gets a white fill + black icon so it reads
    /// first at a glance.
    private var toolCluster: some View {
        HStack(spacing: 8) {
            toolIconButton(.paint, system: "paintbrush.fill")
            toolIconButton(.erase, system: "eraser.fill")
            toolIconButton(.eyedropper, system: "eyedropper")
        }
    }

    @ViewBuilder
    private func toolIconButton(_ t: CreatorState.Tool, system: String) -> some View {
        let selected = state.tool == t
        Button {
            state.tool = t
            state.cancelDrag()
        } label: {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Color.white : Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Color.clear : Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            switch t {
            case .paint: return "Paint"
            case .erase: return "Erase"
            case .eyedropper: return "Pick color"
            }
        }())
    }

    // ─── Bottom: tools + validation ─────────────────────────────────

    /// Live-computed puzzle + validation. `nil` until at least one
    /// gradient is laid. Recomputed on every render — cheap enough.
    private var built: (puzzle: Puzzle, validation: CreatorValidation)? {
        CreatorBuilder.build(from: state)
    }

    private var toolBar: some View {
        VStack(spacing: 10) {
            validationBanner

            // Four equal-flex buttons with generous touch targets —
            // Submit moved into the top-right overflow menu so this
            // row has room. Icons sit above labels so the buttons
            // stay legible even at the 14pt step.
            HStack(spacing: 10) {
                bottomBarButton(
                    system: "arrow.uturn.backward",
                    label: "Undo",
                    disabled: state.gradients.isEmpty,
                    tone: .neutral
                ) { state.undo() }

                bottomBarButton(
                    system: "trash",
                    label: "Clear",
                    disabled: state.gradients.isEmpty,
                    tone: .destructive
                ) { state.clearAll() }

                shareBottomButton

                bottomBarButton(
                    system: "square.and.arrow.down.fill",
                    label: "Save",
                    disabled: !(built?.validation.playable ?? false),
                    tone: .prominent
                ) {
                    if let b = built, b.validation.playable {
                        persistIfNeeded(puzzle: b.puzzle, difficulty: b.validation.difficulty)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 14)

            submitStatusRow

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
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OK.toColor(color))
                .frame(width: 50, height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick color")
    }
}

private struct ShiftChip: View {
    let startColor: OKLCh
    let deltaL: Double
    let deltaC: Double
    let deltaH: Double
    let onTap: () -> Void

    /// The five-cell preview: startColor at index 0, then shifted by
    /// (ΔL, Δc, Δh) per step. Mirrors the trajectory the shift would
    /// actually paint onto the canvas so the chip previews the
    /// outcome rather than a generic icon.
    private var previewColors: [OKLCh] {
        (0..<5).map { i in
            let t = Double(i)
            return OKLCh(
                L: startColor.L + deltaL * t,
                c: startColor.c + deltaC * t,
                h: OK.normH(startColor.h + deltaH * t)
            )
        }
    }

    var body: some View {
        Button(action: onTap) {
            // Five-stripe gradient preview in a chip matching the
            // solid ColorChip footprint (50x50). Drops the 'Shift'
            // text + Δh readout so the header row stays tight.
            HStack(spacing: 1) {
                ForEach(Array(previewColors.enumerated()), id: \.offset) { _, c in
                    Rectangle()
                        .fill(OK.toColor(c))
                        .frame(width: 10, height: 50)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick shift")
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
            let manualLocks = state.manualLocks
            let autoLocks = state.autoLockedCells
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
                                    isLocked: manualLocks.contains(idx) || autoLocks.contains(idx)
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
