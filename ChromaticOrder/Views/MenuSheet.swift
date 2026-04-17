//  Hamburger dropdown. Renders at the top-right, passes through
//  game actions via the shared GameState. Accessibility-specific
//  controls (Reduce Motion, Color Blindness, contrast, L/c clamps)
//  live in a dedicated sheet so the top-level menu stays focused on
//  game actions.

import SwiftUI

struct MenuSheet: View {
    @Bindable var game: GameState
    @Binding var menuOpen: Bool
    @Binding var creatorOpen: Bool
    @Binding var feedbackOpen: Bool
    @Binding var accessibilityOpen: Bool
    @State private var showResetConfirm = false

    var body: some View {
        GeometryReader { _ in
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
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
                    menuButton(label: "Accessibility…") {
                        menuOpen = false
                        accessibilityOpen = true
                    }

                    Divider().padding(.vertical, 4)

                    Button {
                        showResetConfirm = true
                    } label: {
                        Text("Reset Progress")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.8, green: 0.2, blue: 0.2))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.8, green: 0.2, blue: 0.2), lineWidth: 1.5)
                            )
                    }
                }
                .padding(8)
                .frame(minWidth: 260)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
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
        // Bigger tap targets than the pre-accessibility-sheet version:
        // 14pt font, 13pt vertical padding, 14pt horizontal. More
        // comfortable on larger phones and easier to hit with your
        // thumb mid-drag-cancellation.
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(danger
                    ? Color(red: 0.8, green: 0.2, blue: 0.2)
                    : Color(red: 0.2, green: 0.2, blue: 0.2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 13)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }
}
