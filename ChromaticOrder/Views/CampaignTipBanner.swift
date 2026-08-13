//  The campaign's one-line coaching notes. Sits low on the screen, above
//  the bank, where it explains the thing this level introduces — "the
//  marked cell belongs to both gradients", "solve the easier stroke first".
//  Tap to clear; each note is shown once ever (see CampaignStore).

import SwiftUI

struct CampaignTipBanner: View {
    let text: String
    let onDismiss: () -> Void

    @State private var shown = false

    var body: some View {
        VStack {
            // Below the board, above the bank: the tip talks about the board
            // and must not sit on top of the swatches the player needs to
            // drag. The bank grows upward from the bottom, so this rides the
            // gap between them rather than the screen edge.
            Spacer()
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 28)
                // Clears a three-row bank with room to spare.
                .padding(.bottom, 168)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 10)
        }
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.25)) { shown = true }
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

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.22)) { shown = false }
        onDismiss()
    }
}
