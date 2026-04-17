//  Edge glow overlay — a soft frame around the viewport in the held
//  color. Implemented as four linear gradients (one from each edge,
//  fading to clear before the center) stacked in a ZStack. A single
//  radial gradient is the obvious choice but radially the corners are
//  ~1.4× farther from the center than the edge midpoints, so the side
//  edges get clipped off — looks like "glow only at top and bottom."
//  Per-edge linear gradients give uniform strength at every edge.

import SwiftUI

struct EdgeVignetteView: View {
    let color: OKLCh?
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { _ in
            if let c = color {
                let strong = OK.toColor(c, opacity: 0.28)
                let faint  = OK.toColor(c, opacity: 0.18)
                let clear  = OK.toColor(c, opacity: 0)
                ZStack {
                    // Top edge
                    LinearGradient(
                        stops: [
                            .init(color: strong, location: 0.0),
                            .init(color: faint,  location: 0.05),
                            .init(color: clear,  location: 0.30),
                        ],
                        startPoint: .top, endPoint: .bottom)
                    // Bottom edge
                    LinearGradient(
                        stops: [
                            .init(color: clear,  location: 0.70),
                            .init(color: faint,  location: 0.95),
                            .init(color: strong, location: 1.00),
                        ],
                        startPoint: .top, endPoint: .bottom)
                    // Left edge
                    LinearGradient(
                        stops: [
                            .init(color: strong, location: 0.0),
                            .init(color: faint,  location: 0.05),
                            .init(color: clear,  location: 0.30),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                    // Right edge
                    LinearGradient(
                        stops: [
                            .init(color: clear,  location: 0.70),
                            .init(color: faint,  location: 0.95),
                            .init(color: strong, location: 1.00),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                }
                .blendMode(.normal)
                // Bounce in / bounce out — a spring with low damping so
                // the vignette slightly overshoots on appear and settles,
                // same on dismiss. Response controls duration; damping
                // controls how much it oscillates before resting.
                .animation(reduceMotion
                           ? nil
                           : .spring(response: 0.45, dampingFraction: 0.62),
                           value: c)
                .transition(.opacity.animation(reduceMotion
                    ? .linear(duration: 0)
                    : .spring(response: 0.45, dampingFraction: 0.62)))
            }
        }
        .ignoresSafeArea()
    }
}
