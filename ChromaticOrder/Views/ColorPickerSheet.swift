//  OKLCh color picker sheet. Three sliders — L (lightness), c (chroma),
//  h (hue) — with a big live preview swatch at top. Values clamp to
//  the game's usable band so the picked colors stay visually coherent
//  with generator output.

import SwiftUI

struct ColorPickerSheet: View {
    @Binding var color: OKLCh
    /// When `allowNil` is true, the sheet shows a "No end color (shift
    /// mode)" toggle that sets a separate binding. Used on the End
    /// color chip so the creator can drop the endpoint entirely.
    var allowNil: Bool = false
    @Binding var isNilled: Bool
    var title: String = "Color"
    @Environment(\.dismiss) private var dismiss

    init(color: Binding<OKLCh>, title: String = "Color") {
        self._color = color
        self.title = title
        self.allowNil = false
        self._isNilled = .constant(false)
    }

    init(color: Binding<OKLCh>, isNilled: Binding<Bool>, title: String = "End color") {
        self._color = color
        self._isNilled = isNilled
        self.allowNil = true
        self.title = title
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                // Preview strip — full hue/chroma/lightness at once so
                // the player sees the color they're building, not just
                // three numeric sliders.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isNilled ? AnyShapeStyle(stripePattern) : AnyShapeStyle(OK.toColor(color)))
                    .frame(height: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                if allowNil {
                    Toggle(isOn: $isNilled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shift mode (no end color)")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Gradient advances by a per-step delta instead of lerping to an endpoint.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.accentColor)
                    .padding(.horizontal, 20)
                }

                if !isNilled {
                    VStack(spacing: 14) {
                        LCHSlider(label: "Lightness",
                                  value: Binding(
                                    get: { color.L },
                                    set: { color.L = max(OK.lMin, min(OK.lMax, $0)) }
                                  ),
                                  range: OK.lMin...OK.lMax,
                                  format: { String(format: "%.2f", $0) })
                        LCHSlider(label: "Chroma",
                                  value: Binding(
                                    get: { color.c },
                                    set: { color.c = max(OK.cMin, min(OK.cMax, $0)) }
                                  ),
                                  range: OK.cMin...OK.cMax,
                                  format: { String(format: "%.2f", $0) })
                        LCHSlider(label: "Hue",
                                  value: Binding(
                                    get: { color.h },
                                    set: { color.h = OK.normH($0) }
                                  ),
                                  range: 0...360,
                                  format: { String(format: "%.0f°", $0) })
                    }
                    .padding(.horizontal, 20)
                }
                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // Subtle striped pattern behind the preview when the endpoint is
    // disabled — communicates "no color here" without relying on an
    // icon or a gray placeholder (which would just look like gray).
    private var stripePattern: some ShapeStyle {
        LinearGradient(
            colors: [Color.gray.opacity(0.18), Color.gray.opacity(0.08), Color.gray.opacity(0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

private struct LCHSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(format(value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
