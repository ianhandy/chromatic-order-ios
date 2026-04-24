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
    @State private var favorites: [GalleryPuzzle] = []
    @State private var collections: [GalleryCollection] = []
    @State private var creatorOpen = false
    @State private var editingPuzzle: GalleryPuzzle? = nil
    @State private var renameTarget: GalleryPuzzle? = nil
    @State private var renameText: String = ""
    @State private var movingPuzzle: GalleryPuzzle? = nil
    @State private var importing = false
    @State private var importError: String? = nil
    /// Inline feedback after a Submit-to-Community action from the
    /// context menu. The message is shown as a short alert so the
    /// player sees the server's response (pending / already-approved
    /// / already-rejected / network error) without opening the full
    /// Creator sheet.
    @State private var submitAlertMessage: String? = nil
    @State private var submittingPuzzleId: String? = nil
    /// Community sheet presented from the social button.
    @State private var communityOpen = false
    /// Fetched community feed for the new Community Puzzles section
    /// shown inline in the Gallery list. nil = still loading; empty
    /// array = backend returned nothing; populated = show rows.
    @State private var communityEntries: [CommunityPuzzleEntry]? = nil
    /// New/rename flow for collections. `collectionRenameTarget` is
    /// nil when the alert is for creation; otherwise holds the target.
    @State private var collectionAlertOpen = false
    @State private var collectionRenameTarget: GalleryCollection? = nil
    @State private var collectionNameText: String = ""
    @State private var collectionToDelete: GalleryCollection? = nil

    var body: some View {
        NavigationStack {
            Group {
                if puzzles.isEmpty && favorites.isEmpty && collections.isEmpty {
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
                    // Social button — jumps to the Community feed
                    // from the Gallery top bar. Placed left of the
                    // + so 'browse community' and 'create your own'
                    // sit together as the two outward-facing actions.
                    Button {
                        communityOpen = true
                    } label: {
                        Image(systemName: "person.2.fill")
                    }
                    .accessibilityLabel("Browse community puzzles")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            creatorOpen = true
                        } label: {
                            Label("Create New", systemImage: "square.and.pencil")
                        }
                        Button {
                            collectionRenameTarget = nil
                            collectionNameText = ""
                            collectionAlertOpen = true
                        } label: {
                            Label("New Collection", systemImage: "folder.badge.plus")
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
            .navigationDestination(for: GalleryCollection.self) { col in
                CollectionDetailView(game: game, started: $started, collection: col)
            }
        }
        .fullScreenCover(isPresented: $creatorOpen, onDismiss: reload) {
            CreatorView(game: game, saveOnPlay: true)
        }
        .fullScreenCover(item: $editingPuzzle, onDismiss: reload) { puzzle in
            CreatorView(game: game, saveOnPlay: false, editing: puzzle)
        }
        .sheet(item: $movingPuzzle, onDismiss: reload) { puzzle in
            MoveToCollectionSheet(puzzle: puzzle, currentCollection: nil)
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
        .alert(
            collectionRenameTarget == nil ? "New Collection" : "Rename Collection",
            isPresented: $collectionAlertOpen
        ) {
            TextField("Collection name", text: $collectionNameText)
            Button("Save") { commitCollectionName() }
            Button("Cancel", role: .cancel) {
                collectionAlertOpen = false
                collectionRenameTarget = nil
                collectionNameText = ""
            }
        } message: {
            Text(collectionRenameTarget == nil
                 ? "Group puzzles into a campaign or theme."
                 : "Rename this collection.")
        }
        .alert(
            "Delete collection?",
            isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { commitCollectionDelete() }
            Button("Cancel", role: .cancel) { collectionToDelete = nil }
        } message: {
            if let c = collectionToDelete, c.puzzleCount > 0 {
                Text("“\(c.name)” contains \(c.puzzleCount) puzzle\(c.puzzleCount == 1 ? "" : "s"). They'll be deleted too.")
            } else {
                Text("This can't be undone.")
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Community", isPresented: Binding(
            get: { submitAlertMessage != nil },
            set: { if !$0 { submitAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { submitAlertMessage = nil }
        } message: {
            Text(submitAlertMessage ?? "")
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
        .sheet(isPresented: $communityOpen) {
            CommunityListView(game: game)
        }
        .task {
            // One-shot community-feed pull on first appear so the
            // inline Community Puzzles section renders real rows
            // (or an empty-placeholder when the pool is still small).
            // Errors collapse to empty so the section stays visually
            // stable — the full CommunityListView surfaces network
            // issues with its own Try-again path.
            if communityEntries == nil {
                let (entries, _) = await CommunityStore.fetchFeed(sort: .top, limit: 20)
                await MainActor.run { communityEntries = entries }
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
            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(collections) { col in
                        NavigationLink(value: col) {
                            collectionRow(col)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                collectionToDelete = col
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                collectionRenameTarget = col
                                collectionNameText = col.name
                                collectionAlertOpen = true
                            } label: {
                                Label("Rename", systemImage: "tag")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button {
                                collectionRenameTarget = col
                                collectionNameText = col.name
                                collectionAlertOpen = true
                            } label: {
                                Label("Rename", systemImage: "tag")
                            }
                            Button(role: .destructive) {
                                collectionToDelete = col
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Your puzzles") {
                if puzzles.isEmpty {
                    Text("No saved puzzles yet. Tap + to create one.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(puzzles) { puzzle in
                        GalleryRowWithActions(
                            puzzle: puzzle,
                            onPlay: { play(puzzle) },
                            onEdit: { editingPuzzle = puzzle }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                try? GalleryStore.delete(puzzle)
                                reload()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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

            Section("Favorites") {
                if favorites.isEmpty {
                    Text("Favorited puzzles from challenge / zen show up here.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(favorites) { puzzle in
                        GalleryRowWithActions(
                            puzzle: puzzle,
                            onPlay: { play(puzzle, favoriteURL: puzzle.url) },
                            // Favorites can't be edited in place —
                            // they're stored .kroma snapshots, not
                            // gallery entries. Hide the Edit button
                            // so the row reflects available actions.
                            onEdit: nil
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                try? FavoritesStore.delete(puzzle)
                                reload()
                            } label: {
                                Label("Remove", systemImage: "star.slash")
                            }
                        }
                        .contextMenu {
                            Button {
                                play(puzzle, favoriteURL: puzzle.url)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            Button(role: .destructive) {
                                try? FavoritesStore.delete(puzzle)
                                reload()
                            } label: {
                                Label("Remove from favorites", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }

            Section("Community puzzles") {
                if let list = communityEntries, list.isEmpty {
                    Text("No community puzzles yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if communityEntries == nil {
                    Text("Loading…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let list = communityEntries {
                    ForEach(list) { entry in
                        CommunityGalleryRow(entry: entry) {
                            playCommunityEntry(entry)
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        puzzles = GalleryStore.all()
        favorites = FavoritesStore.all()
        collections = GalleryStore.collections()
    }

    private func commitCollectionName() {
        let name = collectionNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let target = collectionRenameTarget {
            try? GalleryStore.renameCollection(target, to: name)
        } else {
            _ = try? GalleryStore.createCollection(name: name.isEmpty ? "Untitled" : name)
        }
        collectionAlertOpen = false
        collectionRenameTarget = nil
        collectionNameText = ""
        reload()
    }

    private func commitCollectionDelete() {
        guard let target = collectionToDelete else { return }
        try? GalleryStore.deleteCollection(target)
        collectionToDelete = nil
        reload()
    }

    @ViewBuilder
    private func collectionRow(_ col: GalleryCollection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(col.name)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(col.puzzleCount) puzzle\(col.puzzleCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Load a community-feed puzzle into the game. Shares the same
    /// loadCustomPuzzle bridge Gallery entries use, with fromGallery=
    /// true so the in-game hamburger's back row reads "← gallery"
    /// and returns here instead of the main menu.
    private func playCommunityEntry(_ entry: CommunityPuzzleEntry) {
        guard let built = CreatorCodec.rebuild(entry.doc, level: entry.level) else { return }
        game.loadCustomPuzzle(built, favoriteURL: nil, fromGallery: true)
        started = true
        dismiss()
    }

    private func play(_ puzzle: GalleryPuzzle, favoriteURL: URL? = nil) {
        guard let built = CreatorCodec.rebuild(puzzle.doc) else { return }
        game.loadCustomPuzzle(built, favoriteURL: favoriteURL, fromGallery: true)
        // Close gallery + drop into game. The dismiss chain routes
        // through the parent sheet's onDismiss; MenuView flips
        // `started` to true there.
        started = true
        dismiss()
    }

    /// Submit a gallery puzzle to the community moderation queue.
    /// Server dedupes by content hash — resubmitting a puzzle that's
    /// already been submitted just echoes back its current status
    /// so the alert reads 'already pending / approved / rejected'
    /// instead of queuing duplicates.
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
}

// ─── Row ────────────────────────────────────────────────────────────

struct GalleryRow: View {
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

/// Gallery row with inline Play (+ optional Edit) action buttons on
/// the right side. Replaces the whole-row tap-to-play gesture that
/// used to be the only way in. Tapping the row's title area still
/// plays; the buttons give an unambiguous affordance + separate the
/// Edit path without needing swipe or long-press.
struct GalleryRowWithActions: View {
    let puzzle: GalleryPuzzle
    let onPlay: () -> Void
    /// nil = row is read-only (favorites don't edit in place).
    let onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Tappable row body — palette strip + title. Wrapped in
            // a plain Button so voice-over announces the row as one
            // action while the action buttons on the right stay
            // individually reachable.
            Button(action: onPlay) {
                GalleryRow(puzzle: puzzle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                GalleryActionButton(system: "play.fill",
                                    accessibilityLabel: "Play",
                                    tone: .green) { onPlay() }
                if let onEdit {
                    GalleryActionButton(system: "pencil",
                                        accessibilityLabel: "Edit",
                                        tone: .blue) { onEdit() }
                }
            }
        }
    }
}

/// One-off community row: preview swatch + submitter name + Play.
/// No Edit/Rename/Delete — community puzzles are read-only from
/// the Gallery's perspective.
struct CommunityGalleryRow: View {
    let entry: CommunityPuzzleEntry
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        let cells = entry.doc.gradients.first?.cells.prefix(5) ?? []
                        ForEach(Array(cells.enumerated()), id: \.offset) { (_, cell) in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(OK.toColor(OKLCh(L: cell.L, c: cell.C, h: cell.h)))
                                .frame(width: 14, height: 30)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.submitterName?.isEmpty == false
                             ? entry.submitterName!
                             : "lv \(entry.level)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("lv \(entry.level) · ▲\(entry.upCount)  ▼\(entry.downCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            GalleryActionButton(system: "play.fill",
                                accessibilityLabel: "Play",
                                tone: .green,
                                action: onPlay)
        }
        .padding(.vertical, 8)
    }
}

private struct GalleryActionButton: View {
    enum Tone { case green, blue }
    let system: String
    let accessibilityLabel: String
    let tone: Tone
    let action: () -> Void

    var body: some View {
        let color: Color = {
            switch tone {
            case .green: return Color(red: 0.36, green: 0.78, blue: 0.45)
            case .blue:  return Color(red: 0.26, green: 0.52, blue: 0.96)
            }
        }()
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(color)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
