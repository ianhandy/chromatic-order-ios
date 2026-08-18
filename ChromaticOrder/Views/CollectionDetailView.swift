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
    @Environment(FullVersionStore.self) private var fullVersion
    @State private var puzzles: [GalleryPuzzle] = []
    @State private var creatorOpen = false
    @State private var fullVersionOpen = false
    @State private var editingPuzzle: GalleryPuzzle? = nil
    @State private var renameTarget: GalleryPuzzle? = nil
    @State private var renameText: String = ""
    @State private var movingPuzzle: GalleryPuzzle? = nil
    @State private var importing = false
    @State private var importError: String? = nil
    /// Base size for the empty-state glyph. `@ScaledMetric` so it grows
    /// with Dynamic Type instead of sitting fixed at 44pt.
    @ScaledMetric(relativeTo: .largeTitle) private var emptyStateIconSize: CGFloat = 44
    /// Submit-to-Community feedback — same pattern as GalleryView.
    @State private var submitAlertMessage: String? = nil
    @State private var submittingPuzzleId: String? = nil
    /// Mirrors GalleryView's focus pattern — when the player exits a
    /// puzzle that was launched from this collection, the back-arrow
    /// pushes us back here and we tint the row briefly so the player
    /// re-acquires their place.
    @State private var highlightedPuzzleId: String? = nil
    /// In-flight disk load — cancelled and replaced by the next
    /// reload so overlapping passes can't land out of order.
    @State private var loadTask: Task<Void, Never>? = nil
    /// False until the first load lands, so the empty placeholder
    /// never flashes ahead of the rows.
    @State private var didLoad = false

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if !didLoad {
                    Color.clear
                } else if puzzles.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .onChange(of: puzzles.map(\.id)) { _, _ in
                focusReturnedPuzzleIfNeeded(proxy: proxy)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        openCreator()
                    } label: {
                        Label("New puzzle", systemImage: fullVersion.isUnlocked || fullVersion.canTry(.creator)
                              ? "square.and.pencil" : "lock.fill")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import…", systemImage: "tray.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                        .kromaHitTarget()
                }
                .accessibilityLabel("add")
            }
        }
        .fullScreenCover(isPresented: $creatorOpen, onDismiss: reload) {
            CreatorView(game: game, saveOnPlay: true, collection: collection)
        }
        .fullScreenCover(item: $editingPuzzle, onDismiss: reload) { puzzle in
            CreatorView(game: game, saveOnPlay: false, editing: puzzle)
        }
        .sheet(isPresented: $fullVersionOpen) {
            FullVersionView(focus: .creator)
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
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var empty: some View {
        VStack(spacing: Kroma.Space.m) {
            Image(systemName: "folder")
                .font(.system(size: emptyStateIconSize))
                .foregroundStyle(.secondary)
            Text("No puzzles in this collection yet")
                .font(Kroma.font(.subheadline, .semibold))
            Text("Create one, or move existing puzzles here.")
                .font(Kroma.font(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                openCreator()
            } label: {
                Label("Create New", systemImage: "plus")
                    .font(Kroma.font(.subheadline, .bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, Kroma.Space.s)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(puzzles) { puzzle in
                GalleryRow(puzzle: puzzle)
                    .contentShape(Rectangle())
                    .id(puzzle.id)
                    .listRowBackground(
                        highlightedPuzzleId == puzzle.id
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear
                    )
                    .onTapGesture { play(puzzle) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            try? GalleryStore.delete(puzzle)
                            reload()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            openCreator(editing: puzzle)
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
                            openCreator(editing: puzzle)
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
        .alert("Community", isPresented: Binding(
            get: { submitAlertMessage != nil },
            set: { if !$0 { submitAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { submitAlertMessage = nil }
        } message: {
            Text(submitAlertMessage ?? "")
        }
    }

    /// Same off-main read as GalleryView.reload — every puzzle in the
    /// collection is a JSON file that has to be decoded, and doing
    /// that inline on push made the navigation animation stutter.
    private func reload() {
        loadTask?.cancel()
        let target = collection
        loadTask = Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) {
                GalleryStore.puzzles(in: target)
            }.value
            guard !Task.isCancelled else { return }
            puzzles = loaded
            didLoad = true
            loadTask = nil
        }
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
        game.loadCustomPuzzle(
            built,
            favoriteURL: nil,
            fromGallery: true,
            galleryPuzzleId: puzzle.id,
            galleryCollectionId: collection.id,
            allowsFavorite: false,
            title: puzzle.doc.name
        )
        started = true
        dismiss()
    }

    private func openCreator(editing puzzle: GalleryPuzzle? = nil) {
        guard fullVersion.isUnlocked || fullVersion.canTry(.creator) else {
            fullVersionOpen = true
            return
        }
        if let puzzle {
            editingPuzzle = puzzle
        } else {
            creatorOpen = true
        }
    }

    /// Mirror of GalleryView.focusReturnedPuzzleIfNeeded: scroll to
    /// the row of the just-played puzzle and tint it briefly. Only
    /// fires when the player returns from a play that originated in
    /// THIS collection (currentGalleryCollectionId matches), so a
    /// stale id from a sibling collection doesn't mis-target.
    private func focusReturnedPuzzleIfNeeded(proxy: ScrollViewProxy) {
        guard game.currentGalleryCollectionId == collection.id,
              let id = game.currentGalleryPuzzleId,
              puzzles.contains(where: { $0.id == id })
        else { return }
        game.currentGalleryPuzzleId = nil
        game.currentGalleryCollectionId = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(id, anchor: .center)
            }
            highlightedPuzzleId = id
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                highlightedPuzzleId = nil
            }
        }
    }

    /// Same submit flow as GalleryView.submitToCommunity — kept per-
    /// view so each screen owns its own alert state without threading
    /// it through a shared environment object.
    private func submitToCommunity(_ puzzle: GalleryPuzzle) {
        guard submittingPuzzleId == nil else { return }
        guard let built = CreatorCodec.rebuild(puzzle.doc) else {
            submitAlertMessage = "Couldn't rebuild this puzzle for submission."
            return
        }
        submittingPuzzleId = puzzle.id
        let level = built.level
        let submitterName = puzzle.doc.name
        let doc = puzzle.doc
        Task {
            let result = await CommunityStore.submit(
                doc: doc, level: level, submitterName: submitterName
            )
            await MainActor.run {
                submittingPuzzleId = nil
                switch result {
                case .success(let resp):
                    switch resp.status ?? "pending" {
                    case "approved":
                        submitAlertMessage = "Already approved — your puzzle is live in the community pool."
                    case "rejected":
                        submitAlertMessage = "This puzzle was previously rejected by the moderator."
                    default:
                        submitAlertMessage = "Submitted — awaiting review."
                    }
                case .failure(let err):
                    submitAlertMessage = "Submit failed: \(err.localizedDescription)"
                }
            }
        }
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
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var didLoad = false

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
                    if !didLoad {
                        EmptyView()
                    } else if collections.isEmpty {
                        Text("No collections yet")
                            .font(Kroma.font(.footnote))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collections) { col in
                            if col.id != currentCollection?.id {
                                Button {
                                    move(to: col)
                                } label: {
                                    HStack {
                                        Label {
                                            Text(col.name)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        } icon: {
                                            Image(systemName: "folder")
                                        }
                                        Spacer()
                                        Text("\(col.puzzleCount)")
                                            .font(Kroma.font(.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .kromaSheet("move puzzle") { dismiss() }
            .onAppear {
                loadTask?.cancel()
                loadTask = Task { @MainActor in
                    let loaded = await Task.detached(priority: .userInitiated) {
                        GalleryStore.collections()
                    }.value
                    guard !Task.isCancelled else { return }
                    collections = loaded
                    didLoad = true
                    loadTask = nil
                }
            }
            .onDisappear {
                loadTask?.cancel()
                loadTask = nil
            }
        }
    }

    private func move(to target: GalleryCollection?) {
        _ = try? GalleryStore.movePuzzle(puzzle, to: target)
        dismiss()
    }
}
