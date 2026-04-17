//  Edge glow overlay — inset box-shadow equivalent. Paints the held
//  color as a soft frame around the viewport, strong at the edges and
//  fading toward the center. No iOS "inset" shadow primitive, so we
//  use nested radial/linear gradients in a Canvas-like overlay.

import SwiftUI

struct EdgeVignetteView: View {
    let color: OKLCh?
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let maxDim = max(w, h)
            if let c = color {
                let baseColor = OK.toColor(c, opacity: 0.28)
                let innerColor = OK.toColor(c, opacity: 0)
                // Radial gradient from viewport-center fade-to-edge. Max
                // radius slightly smaller than maxDim/2 so the outer ring
                // hits full strength right at the corners.
                Rectangle()
                    .fill(
                        RadialGradient(
                            colors: [innerColor, innerColor, baseColor],
                            center: .center,
                            startRadius: maxDim * 0.25,
                            endRadius: maxDim * 0.58
                        )
                    )
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: c)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
}
