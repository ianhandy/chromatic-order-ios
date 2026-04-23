//  Reusable screen-dim layer for focused UI moments. When a tooltip
//  / inline confirmation / modal element wants the player's full
//  attention, mount `FocusDim` above the backdrop and below that
//  element in the ZStack. Everything in the layers below the dim
//  darkens; everything at a higher zIndex stays readable.
//
//  Not a mask-based cutout — just a flat opacity layer. Sub-views
//  that should stay lit are rendered ABOVE the dim via their own
//  .zIndex(…) values. This keeps the API trivially composable.

import SwiftUI

struct FocusDim: View {
    /// Whether the dim is on. Drives the fade animation.
    let active: Bool
    /// How dark the dim gets at full activation. 0.55 = a pronounced
    /// vignette without full blackout; stuff underneath is still
    /// legible.
    var strength: Double = 0.55

    var body: some View {
        Color.black
            .opacity(active ? strength : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.30), value: active)
    }
}
