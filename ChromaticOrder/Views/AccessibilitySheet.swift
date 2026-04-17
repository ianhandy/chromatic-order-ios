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
//  All changes defer regeneration until the sheet closes (same pattern
//  as the menu's CB cycle) so mid-adjustment sliders don't thrash the
//  canvas.

import SwiftUI

struct AccessibilitySheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

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
                    Button(role: .destructive) {
                        game.resetAccessibility()
                    } label: {
                        Text("Reset to defaults")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
