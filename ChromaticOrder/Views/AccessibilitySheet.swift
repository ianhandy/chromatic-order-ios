//  Accessibility settings. All adjustments here reshape the generator's
//  color palette for the player's specific needs:
//
//  • Contrast — multiplier on per-step shift ranges (rangeScale in
//    GenConfig). Higher = bigger jumps between adjacent cells.
//  • Luminance clamp — narrows the allowed L window. Useful when
//    bright-on-dark or dark-on-dark is hard to read.
//  • Saturation clamp — narrows the allowed chroma window.
//  • Color blindness — picks the simulation mode the generator builds
//    under. Distances are measured in the player's perceptual space
//    so the puzzle stays solvable.
//  • Reduce motion — turns off continuous sway + burst animations.
//
//  The last section ("for testing only") is the odd one out: it is not
//  an accessibility aid but a test-harness knob that compresses the
//  board's colors and loosens the same-color test used when judging
//  answers. See TestingFilter.swift.
//
//  All changes defer regeneration until the sheet closes (same pattern
//  as the menu's CB cycle) so mid-adjustment sliders don't thrash the
//  canvas.

import SwiftUI

struct AccessibilitySheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var showResetProgress = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    contrastSlider
                } header: {
                    Text("Contrast")
                } footer: {
                    Text("Multiplier on the generator's per-step shift. Higher makes adjacent cells easier to distinguish.")
                }

                Section {
                    luminanceSliders
                } header: {
                    Text("Luminance clamp")
                } footer: {
                    Text("Tighten to avoid very dark or very bright cells.")
                }

                Section {
                    saturationSliders
                } header: {
                    Text("Saturation clamp")
                } footer: {
                    Text("Tighten if highly saturated colors are hard to read.")
                }

                Section {
                    cbPicker
                } header: {
                    Text("Color blindness")
                } footer: {
                    Text("Puzzles rebuild using a perceptual model tuned for the selected vision, so steps stay distinguishable.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { game.reduceMotion },
                        set: { _ in game.toggleReduceMotion() }
                    )) {
                        Text("Reduce motion")
                    }
                } footer: {
                    Text("Disables the continuous bank sway, wrong-answer shake, and solved-burst flash.")
                }

                Section {
                    labeledSlider(
                        label: "Max gap",
                        value: $game.doubleTapInterval,
                        range: 0.15...0.60,
                        step: 0.01,
                        format: { String(format: "%.2fs", $0) }
                    )
                } header: {
                    Text("Double-tap zoom")
                } footer: {
                    Text("Max time between taps that still counts as a double-tap. Lower = tighter; raise it if taps feel missed.")
                }

                Section {
                    Toggle("Magnetism", isOn: $game.magnetismEnabled)
                    Toggle("Edge vignette", isOn: $game.edgeVignetteEnabled)
                    Toggle("Solved glow", isOn: $game.solvedGlowEnabled)
                    Toggle("Menu backdrop", isOn: $game.menuBackdropEnabled)
                    if game.menuBackdropEnabled {
                        Picker("Menu style", selection: $game.menuStyle) {
                            ForEach(MenuStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Toggle("Show timer", isOn: $game.timerVisible)
                } header: {
                    Text("Visual effects")
                } footer: {
                    // Only the two facts a player can't discover by
                    // flipping the switch and looking. The old copy also
                    // described what each menu backdrop looks like, which
                    // the backdrop itself demonstrates the moment you pick
                    // one.
                    Text("Magnetism widens the drop zone around each cell. The timer keeps running for leaderboard submissions even when hidden.")
                }

                Section {
                    Toggle("Background music", isOn: $game.musicEnabled)
                    Toggle("Sound effects", isOn: $game.sfxEnabled)
                    Toggle("Haptics", isOn: $game.hapticsEnabled)
                } header: {
                    Text("Sound & haptics")
                }

                Section {
                    Picker("Menu frame rate", selection: $game.menuFps) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                        Text("120 fps").tag(120)
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Drop to 30 if the menu backdrop feels laggy.")
                }

                Section {
                    AppIconPickerRow()
                } header: {
                    Text("App icon")
                } footer: {
                    Text("Change the home-screen icon's palette. iOS will confirm the swap with a system alert.")
                }

                Section {
                    Button(role: .destructive) {
                        game.resetAccessibility()
                    } label: {
                        Text("Reset to defaults")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                // Reset Progress sits at the very bottom of the
                // settings sheet — destructive, wipes level + hearts.
                // Moved here from the old hamburger menu so the
                // dropdown only carries navigation (home / settings /
                // feedback) and the irreversible action hides behind
                // an extra tap.
                Section {
                    Button(role: .destructive) {
                        showResetProgress = true
                    } label: {
                        Text("Reset progress")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } footer: {
                    Text("Clears your current level and hearts. Ratings are kept.")
                }

                // Last section on purpose. This is not an accessibility
                // aid: it makes the board harder to read AND changes
                // how the game judges answers, so it sits below every
                // real setting with a header that says so.
                Section {
                    Toggle("Enabled", isOn: $game.testingEnabled)
                    if game.testingEnabled {
                        labeledSlider(
                            label: "Similarity compression",
                            value: $game.testingSimilarity,
                            range: TestingFilter.similarityRange,
                            step: 0.05,
                            format: { String(format: "%.2f", $0) }
                        )
                        labeledSlider(
                            label: "Same if closer than",
                            value: $game.testingSameThreshold,
                            range: TestingFilter.thresholdRange,
                            step: 0.5,
                            format: { String(format: "%.1f ΔE", $0) }
                        )
                    }
                } header: {
                    Text("For testing only")
                } footer: {
                    // Trimmed from a paragraph that explained the
                    // implementation ("shrinking every difference by
                    // (1 - compression)"). What a player needs to know
                    // is that this section is not an accessibility aid
                    // and that it changes how answers are judged.
                    Text("Not an accessibility aid. Compression makes the board harder to read, and the threshold loosens what counts as a correct placement.")
                }

            }
            .kromaSheet(Strings.Menu.settings) { dismiss() }
            .alert("Reset all progress?",
                   isPresented: $showResetProgress) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    game.resetProgress()
                    dismiss()
                }
            } message: {
                Text("This clears your current level and hearts. Ratings are kept.")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sub-views

    private var contrastSlider: some View {
        labeledSlider(
            label: "Step magnitude",
            value: $game.contrastScale,
            range: 0.5...1.5,
            step: 0.05,
            format: { String(format: "%.2fx", $0) }
        )
    }

    private var luminanceSliders: some View {
        VStack(spacing: 10) {
            labeledSlider(
                label: "Minimum",
                value: Binding(
                    get: { game.lClampMin },
                    set: { game.lClampMin = min($0, game.lClampMax - 0.05) }
                ),
                range: OK.lMin...OK.lMax,
                step: 0.01,
                format: { String(format: "%.2f", $0) }
            )
            labeledSlider(
                label: "Maximum",
                value: Binding(
                    get: { game.lClampMax },
                    set: { game.lClampMax = max($0, game.lClampMin + 0.05) }
                ),
                range: OK.lMin...OK.lMax,
                step: 0.01,
                format: { String(format: "%.2f", $0) }
            )
        }
    }

    private var saturationSliders: some View {
        VStack(spacing: 10) {
            labeledSlider(
                label: "Minimum",
                value: Binding(
                    get: { game.cClampMin },
                    set: { game.cClampMin = min($0, game.cClampMax - 0.02) }
                ),
                range: OK.cMin...OK.cMax,
                step: 0.005,
                format: { String(format: "%.2f", $0) }
            )
            labeledSlider(
                label: "Maximum",
                value: Binding(
                    get: { game.cClampMax },
                    set: { game.cClampMax = max($0, game.cClampMin + 0.02) }
                ),
                range: OK.cMin...OK.cMax,
                step: 0.005,
                format: { String(format: "%.2f", $0) }
            )
        }
    }

    private var cbPicker: some View {
        Picker(selection: $game.cbMode) {
            ForEach(CBMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        } label: {
            Text("Mode")
        }
        .pickerStyle(.menu)
    }

    /// Slider with a leading label + trailing monospaced readout.
    /// Matches the styling used in ColorPickerSheet so the two sheets
    /// feel like siblings.
    @ViewBuilder
    private func labeledSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: Kroma.Space.xs) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // The visible row is the slider's own label and value, so
            // it's hidden from VoiceOver rather than announced a second
            // time before the control it describes.
            .accessibilityHidden(true)

            Slider(value: value, in: range, step: step)
                .accessibilityLabel(label)
                .accessibilityValue(format(value.wrappedValue))
        }
    }
}

private struct AppIconPickerRow: View {
    @State private var current: AppIconVariant = .pastelPinks

    var body: some View {
        ForEach(AppIconVariant.allCases) { variant in
            Button {
                AppIconPicker.apply(variant)
                current = variant
            } label: {
                HStack(spacing: 12) {
                    PaletteGridThumb(colors: variant.paletteGrid)
                        .frame(width: 38, height: 38)
                    Text(variant.displayName)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if variant == current {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .onAppear { current = AppIconPicker.current }
    }
}

/// 3×3 palette grid rendered inline — used as the preview thumbnail
/// for each app-icon variant in the picker. Takes a row-major
/// 9-element color list and paints a tight grid with a subtle
/// rounded clip so it reads as "a tiny app icon."
private struct PaletteGridThumb: View {
    let colors: [OKLCh]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cornerR = side * 0.22
            let gap: CGFloat = 1
            let cellSide = (side - gap * 4) / 3
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { c in
                            let idx = r * 3 + c
                            let color = idx < colors.count ? colors[idx] : OKLCh(L: 0.5, c: 0, h: 0)
                            Rectangle()
                                .fill(OK.toColor(color))
                                .frame(width: cellSide, height: cellSide)
                        }
                    }
                }
            }
            .padding(gap)
            .frame(width: side, height: side)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerR, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerR, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
        }
    }
}
