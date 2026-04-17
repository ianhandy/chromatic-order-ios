//  OKLCh color picker sheet. Three sliders — L (lightness), c (chroma),
//  h (hue) — with a big live preview swatch at top. Values clamp to
//  the game's usable band so the picked colors stay visually coherent
//  with generator output.
//
//  When `isNilled` is true (shift mode on the End chip), the absolute-
//  color sliders are replaced by ΔL / Δc / Δh sliders that edit the
//  per-step shift directly. Ranges span both signs so the player can
//  set "hue north" (-) or "hue south" (+) without a separate control.

import SwiftUI

struct ColorPickerSheet: View {
    @Binding var color: OKLCh
    /// When `allowNil` is true, the sheet shows a "No end color (shift
    /// mode)" toggle that sets a separate binding. Used on the End
    /// color chip so the creator can drop the endpoint entirely.
    var allowNil: Bool = false
    @Binding var isNilled: Bool
    @Binding var deltaL: Double
    @Binding var deltaC: Double
    @Binding var deltaH: Double
    var title: String = "Color"
    @Environment(\.dismiss) private var dismiss

    init(color: Binding<OKLCh>, title: String = "Color") {
        self._color = color
        self.title = title
        self.allowNil = false
        self._isNilled = .constant(false)
        self._deltaL = .constant(0)
        self._deltaC = .constant(0)
        self._deltaH = .constant(0)
    }

    init(
        color: Binding<OKLCh>,
        isNilled: Binding<Bool>,
        deltaL: Binding<Double>,
        deltaC: Binding<Double>,
        deltaH: Binding<Double>,
        title: String = "End color"
    ) {
        self._color = color
        self._isNilled = isNilled
        self._deltaL = deltaL
        self._deltaC = deltaC
        self._deltaH = deltaH
        self.allowNil = true
        self.title = title
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                // Preview strip — full hue/chroma/lightness at once so
                // the player sees the color they're building, not just
                // three numeric sliders. In shift mode the swatch falls
                // back to the striped placeholder since there's no
                // single "endpoint color" to preview.
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
                } else {
                    // Shift-mode sliders — signed so you can set 'one
                    // direction' or 'the other' directly with the
                    // slider thumb. +hue cycles through the color
                    // wheel one way, −hue the other; +L brightens,
                    // −L darkens; +c saturates, −c desaturates.
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Per-step shift")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 20)
                        VStack(spacing: 14) {
                            LCHSlider(label: "ΔLightness",
                                      value: $deltaL,
                                      range: -0.15...0.15,
                                      format: { String(format: "%+.2f", $0) })
                            LCHSlider(label: "ΔChroma",
                                      value: $deltaC,
                                      range: -0.15...0.15,
                                      format: { String(format: "%+.2f", $0) })
                            LCHSlider(label: "ΔHue",
                                      value: $deltaH,
                                      range: -90...90,
                                      format: { String(format: "%+.0f°", $0) })
                        }
                        .padding(.horizontal, 20)
                    }
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
