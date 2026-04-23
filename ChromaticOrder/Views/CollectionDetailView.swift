//  Drill-down view for a gallery Collection. Same row UI as the main
//  Gallery, but puzzles Created New here save into this collection,
//  and the Move action includes "Move out of collection" back to the
//  gallery root.

import SwiftUI
import UniformTypeIdentifiers

struct CollectionDetailView: View {
    @Bindable var game: GameState
    @Binding var started: Bool
    let collection: GalleryCollection

    @Environment(\.dismiss) private var dismiss
    @State private var puzzles: [GalleryPuzzle] = []
    @State private var creatorOpen = false
    @State private var editingPuzzle: GalleryPuzzle? = nil
    @State private var renameTarget: GalleryPuzzle? = nil
    @State private var renameText: String = ""
    @State private var movingPuzzle: GalleryPuzzle? = nil
    @State private var importing = false
    @State private var importError: String? = nil

    var body: some View {
        Group {
            if puzzles.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .fullScreenCover(isPresented: $creatorOpen, onDismiss: reload) {
            CreatorView(game: game, saveOnPlay: true, collection: collection)
        }
        .fullScreenCover(item: $editingPuzzle, onDismiss: reload) { puzzle in
            CreatorView(game: game, saveOnPlay: false, editing: puzzle)
        }
        .sheet(item: $movingPuzzle, onDismiss: reload) { puzzle in
            MoveToCollectionSheet(puzzle: puzzle, currentCollection: collection)
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

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No puzzles in this collection yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Create one, or move existing puzzles here.")
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
                    .onTapGesture { play(puzzle) }
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
                        Button {
                            movingPuzzle = puzzle
                        } label: {
                            Label("Move to…", systemImage: "folder")
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
        puzzles = GalleryStore.puzzles(in: collection)
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        try? GalleryStore.rename(target, to: renameText)
        renameTarget = nil
        renameText = ""
        reload()
    }

    private func play(_ puzzle: GalleryPuzzle) {
        guard let built = CreatorCodec.rebuild(puzzle.doc) else { return }
        game.loadCustomPuzzle(built, favoriteURL: nil)
        started = true
        dismiss()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            importError = err.localizedDescription
        case .success(let urls):
            var failures = 0
            for url in urls {
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let json = String(data: data, encoding: .utf8),
                      (try? GalleryStore.saveJSON(json, in: collection)) != nil
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
}

// ─── Move picker ───────────────────────────────────────────────────

struct MoveToCollectionSheet: View {
    let puzzle: GalleryPuzzle
    /// The collection the puzzle is currently in, or nil if at root.
    /// Used to hide the entry for its own container from the list.
    var currentCollection: GalleryCollection? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var collections: [GalleryCollection] = []

    var body: some View {
        NavigationStack {
            List {
                if currentCollection != nil {
                    Section {
                        Button {
                            move(to: nil)
                        } label: {
                            Label("Gallery (no collection)", systemImage: "square.grid.3x3")
                        }
                    }
                }
                Section("Collections") {
                    if collections.isEmpty {
                        Text("No collections yet")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collections) { col in
                            if col.id != currentCollection?.id {
                                Button {
                                    move(to: col)
                                } label: {
                                    HStack {
                                        Label(col.name, systemImage: "folder")
                                        Spacer()
                                        Text("\(col.puzzleCount)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move puzzle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { collections = GalleryStore.collections() }
        }
    }

    private func move(to target: GalleryCollection?) {
        _ = try? GalleryStore.movePuzzle(puzzle, to: target)
        dismiss()
    }
}
