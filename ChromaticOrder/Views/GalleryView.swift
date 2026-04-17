//  Gallery — player-authored and received puzzles, grouped together
//  in a scrollable list. Every entry shows a tiny palette preview
//  (first gradient's colors) + difficulty + cell layout. Tapping
//  loads the puzzle via GameState.loadCustomPuzzle and drops the
//  player into the game. Long-press → delete.
//
//  "+ Create New" at the top opens CreatorView; on Play-this there,
//  the puzzle saves to the gallery AND loads into the game.

import SwiftUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @Bindable var game: GameState
    @Binding var started: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var puzzles: [GalleryPuzzle] = []
    @State private var creatorOpen = false
    @State private var editingPuzzle: GalleryPuzzle? = nil
    @State private var renameTarget: GalleryPuzzle? = nil
    @State private var renameText: String = ""
    @State private var importing = false
    @State private var importError: String? = nil

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
                    Menu {
                        Button {
                            creatorOpen = true
                        } label: {
                            Label("Create New", systemImage: "square.and.pencil")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("Import…", systemImage: "tray.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $creatorOpen, onDismiss: reload) {
            CreatorView(game: game, saveOnPlay: true)
        }
        .fullScreenCover(item: $editingPuzzle, onDismiss: reload) { puzzle in
            CreatorView(game: game, saveOnPlay: false, editing: puzzle)
        }
        .alert("Rename puzzle", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Give this puzzle a memorable name.")
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .fileImporter(
            isPresented: $importing,
            // Accept the app's custom UTI plus plain JSON so a .kroma
            // exported without the UTI (e.g. renamed by a mail client)
            // still imports cleanly.
            allowedContentTypes: [
                UTType(filenameExtension: "kroma") ?? .json,
                .json,
            ],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .onAppear(perform: reload)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
        case .success(let urls):
            var failures = 0
            for url in urls {
                // Security-scoped resources — iOS hands us a sandboxed
                // URL that only grants access inside a start/stop
                // bracket. Missing it makes reads fail silently.
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let json = String(data: data, encoding: .utf8),
                      (try? GalleryStore.saveJSON(json)) != nil
                else {
                    failures += 1
                    continue
                }
            }
            if failures == urls.count, !urls.isEmpty {
                importError = "Couldn't read any of the selected files — are they valid .kroma puzzles?"
            } else if failures > 0 {
                importError = "\(failures) of \(urls.count) files couldn't be imported."
            }
            reload()
        }
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        try? GalleryStore.rename(target, to: renameText)
        renameTarget = nil
        renameText = ""
        reload()
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            try? GalleryStore.delete(puzzle)
                            reload()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingPuzzle = puzzle
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                        Button {
                            renameText = puzzle.doc.name ?? ""
                            renameTarget = puzzle
                        } label: {
                            Label("Rename", systemImage: "tag")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button {
                            play(puzzle)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        Button {
                            editingPuzzle = puzzle
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            renameText = puzzle.doc.name ?? ""
                            renameTarget = puzzle
                        } label: {
                            Label("Rename", systemImage: "tag")
                        }
                        Button(role: .destructive) {
                            try? GalleryStore.delete(puzzle)
                            reload()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
            HStack(spacing: 2) {
                let cells = puzzle.doc.gradients.first?.cells.prefix(5) ?? []
                ForEach(Array(cells.enumerated()), id: \.offset) { (_, cell) in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(OK.toColor(OKLCh(L: cell.L, c: cell.C, h: cell.h)))
                        .frame(width: 14, height: 30)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(puzzle.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(puzzle.subtitle) · \(relativeDate(puzzle.createdAt))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private func relativeDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
