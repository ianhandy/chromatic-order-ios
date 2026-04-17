//  Gallery — player-authored and received puzzles, grouped together
//  in a scrollable list. Every entry shows a tiny palette preview
//  (first gradient's colors) + difficulty + cell layout. Tapping
//  loads the puzzle via GameState.loadCustomPuzzle and drops the
//  player into the game. Long-press → delete.
//
//  "+ Create New" at the top opens CreatorView; on Play-this there,
//  the puzzle saves to the gallery AND loads into the game.

import SwiftUI

struct GalleryView: View {
    @Bindable var game: GameState
    @Binding var started: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var puzzles: [GalleryPuzzle] = []
    @State private var creatorOpen = false

    var body: some View {
        NavigationStack {
            Group {
                if puzzles.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        creatorOpen = true
                    } label: {
                        Label("Create New", systemImage: "plus")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $creatorOpen, onDismiss: reload) {
            CreatorView(game: game, saveOnPlay: true)
        }
        .onAppear(perform: reload)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No puzzles yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Create your own or receive one from a friend.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                creatorOpen = true
            } label: {
                Label("Create New", systemImage: "plus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(puzzles) { puzzle in
                GalleryRow(puzzle: puzzle)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        play(puzzle)
                    }
            }
            .onDelete { indexSet in
                for idx in indexSet {
                    try? GalleryStore.delete(puzzles[idx])
                }
                reload()
            }
        }
    }

    private func reload() {
        puzzles = GalleryStore.all()
    }

    private func play(_ puzzle: GalleryPuzzle) {
        guard let built = CreatorCodec.rebuild(puzzle.doc) else { return }
        game.loadCustomPuzzle(built)
        // Close gallery + drop into game. The dismiss chain routes
        // through the parent sheet's onDismiss; MenuView flips
        // `started` to true there.
        started = true
        dismiss()
    }
}

// ─── Row ────────────────────────────────────────────────────────────

private struct GalleryRow: View {
    let puzzle: GalleryPuzzle

    var body: some View {
        HStack(spacing: 12) {
            // Palette swatch — first 6 colors of the first gradient,
            // laid out as a horizontal strip. Gives a visual at-a-
            // glance so the list isn't 40 identical text rows.
            HStack(spacing: 1) {
                let cells = puzzle.doc.gradients.first?.cells.prefix(6) ?? []
                ForEach(Array(cells.enumerated()), id: \.offset) { (_, cell) in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(OK.toColor(OKLCh(L: cell.L, c: cell.C, h: cell.h)))
                        .frame(width: 10, height: 26)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(puzzle.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(relativeDate(puzzle.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
