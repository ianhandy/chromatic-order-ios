//  The campaign's one-line coaching notes. Sits low on the screen, above
//  the bank, where it explains the thing this level introduces — "the
//  marked cell belongs to both gradients", "solve the easier stroke first".
//  Tap to clear; each note is shown once ever (see CampaignStore).

import SwiftUI

struct CampaignTipBanner: View {
    let text: String
    /// Top edge of the bank in global space, once BankView has measured
    /// itself. Nil before the first measurement, or when there is no bank.
    let bankTopY: CGFloat?
    let onDismiss: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            banner(bottomInset: bottomInset(in: geo))
        }
        .allowsHitTesting(false)
        // A rule the board can't demonstrate, so it's spoken as soon as
        // it appears rather than left as a visual-only aside.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            withAnimation(reduceMotion
                          ? .easeOut(duration: 0.01).delay(0.25)
                          : .easeOut(duration: 0.35).delay(0.25)) {
                shown = true
            }
        }
        // Long enough to read twice, then it gets out of the way on its own.
        //
        // The cancellation has to be caught rather than swallowed with `try?`.
        // SwiftUI cancels a `.task` whenever the view goes away or its identity
        // changes, and `try?` turns that into "the nine seconds elapsed", so the
        // banner dismissed itself the instant anything above it re-rendered and
        // cleared the tip for good. A cancelled sleep means the view is going
        // away anyway, so the right response is to do nothing.
        .task {
            do {
                try await Task.sleep(for: .seconds(9))
            } catch {
                return
            }
            dismiss()
        }
    }

    /// How far above the bottom of the screen the banner has to sit to
    /// clear the bank. The bank's height is a function of how many swatches
    /// the level ships, so this was a fixed 168pt that happened to fit the
    /// boards it was written against — a nine-swatch level put the banner
    /// straight across the top row of swatches for the full nine seconds.
    /// Measured beats guessed; the constant survives only as the fallback
    /// for the frame or two before BankView reports its geometry.
    private func bottomInset(in geo: GeometryProxy) -> CGFloat {
        let bottom = geo.frame(in: .global).maxY
        guard let bankTopY, bankTopY > 0, bankTopY < bottom else { return 168 }
        // Never so tall that the banner climbs into the board it describes.
        return min(max(96, bottom - bankTopY + Kroma.Space.m), geo.size.height * 0.6)
    }

    private func banner(bottomInset: CGFloat) -> some View {
        VStack {
            // Below the board, above the bank: the tip talks about the board
            // and must not sit on top of the swatches the player needs to
            // drag. The bank grows upward from the bottom, so this rides the
            // gap between them rather than the screen edge.
            Spacer()
            Text(text.lowercased())
                .font(Kroma.font(.callout, .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Kroma.Space.l)
                .padding(.vertical, Kroma.Space.m)
                .kromaSurface(.panel,
                              in: RoundedRectangle(cornerRadius: Kroma.Radius.card,
                                                   style: .continuous))
                .padding(.horizontal, Kroma.Space.xl)
                .padding(.bottom, bottomInset)
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.22)) { shown = false }
        onDismiss()
    }
}
