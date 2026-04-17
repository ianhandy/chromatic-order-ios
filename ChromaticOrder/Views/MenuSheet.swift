//  Hamburger dropdown. Renders at the top-right, passes through
//  game actions via the shared GameState.

import SwiftUI

struct MenuSheet: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool
    @Binding var creatorOpen: Bool
    @Binding var feedbackOpen: Bool
    @State private var showResetConfirm = false

    var body: some View {
        GeometryReader { _ in
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    menuButton(label: "Switch to \(game.mode == .zen ? "Challenge" : "Zen") Mode") {
                        game.switchMode(); menuOpen = false
                    }
                    menuButton(label: "Reset Puzzle") {
                        game.handleReset(); menuOpen = false
                    }
                    menuButton(label: "Skip (regenerate)") {
                        game.handleSkip(); menuOpen = false
                    }
                    if game.mode == .zen && !game.solved {
                        menuButton(
                            label: game.showIncorrect
                                ? "Hide Incorrect"
                                : "Show Incorrect (−1 level next solve)",
                            danger: !game.showIncorrect
                        ) {
                            game.toggleShowIncorrect(); menuOpen = false
                        }
                    }
                    menuButton(label: "Create Puzzle…") {
                        menuOpen = false
                        creatorOpen = true
                    }
                    menuButton(label: "Send Feedback…") {
                        menuOpen = false
                        feedbackOpen = true
                    }
                    menuButton(label: "Reduce Motion: \(game.reduceMotion ? "On" : "Off")") {
                        game.toggleReduceMotion(); menuOpen = false
                    }
                    menuButton(label: "Color Blindness: \(game.cbMode.shortLabel)") {
                        // Cycle: None → Protan → Deutan → Tritan → Achro → None.
                        // Regenerates the current puzzle under the new vision
                        // so step magnitudes feel right immediately.
                        game.cycleCBMode(); menuOpen = false
                    }

                    Divider().padding(.vertical, 4)

                    Button {
                        showResetConfirm = true
                    } label: {
                        Text("Reset Progress")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(red: 0.8, green: 0.2, blue: 0.2), lineWidth: 1.5)
                            )
                    }
                }
                .padding(6)
                .frame(minWidth: 240)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.82, green: 0.80, blue: 0.78), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                .padding(.trailing, 14)
                .padding(.top, 52)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .transition(.opacity)
        .alert("Reset all progress?",
               isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                game.resetProgress()
                menuOpen = false
            }
        } message: {
            Text("This clears your current level and hearts. Ratings are kept.")
        }
    }

    @ViewBuilder
    private func menuButton(label: String, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(danger
                    ? Color(red: 0.8, green: 0.2, blue: 0.2)
                    : Color(red: 0.2, green: 0.2, blue: 0.2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}
