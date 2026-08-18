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
    @Environment(FullVersionStore.self) private var fullVersion
    @State private var puzzles: [GalleryPuzzle] = []
    @State private var favorites: [GalleryPuzzle] = []
    @State private var collections: [GalleryCollection] = []
    @State private var creatorOpen = false
    @State private var fullVersionOpen = false
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
    /// Fetched community feed for the inline Community Puzzles
    /// section. nil = still loading; empty = backend returned
    /// nothing; populated = show rows. Replaces the old standalone
    /// CommunityListView sheet — the Gallery now owns the full
    /// Top/New sort + expand-to-vote/play interaction inline.
    @State private var communityEntries: [CommunityPuzzleEntry]? = nil
    /// Sort mode for the community section. Server-side; flipping
    /// this re-fetches.
    @State private var communitySort: CommunitySort = .top
    /// Optimistic-vote / async-fetch error surfaced under the section
    /// header so a transient outage doesn't blank the section
    /// silently.
    @State private var communityLoadError: String? = nil
    /// Currently-expanded community row id (only one expanded at a
    /// time). nil = compact for everyone.
    @State private var expandedCommunityId: String? = nil
    /// NavigationStack path. Owned at this level so we can re-push a
    /// CollectionDetailView programmatically when the player exits a
    /// puzzle that was launched from inside that collection.
    @State private var navPath: [GalleryCollection] = []
    /// New/rename flow for collections. `collectionRenameTarget` is
    /// nil when the alert is for creation; otherwise holds the target.
    @State private var collectionAlertOpen = false
    @State private var collectionRenameTarget: GalleryCollection? = nil
    @State private var collectionNameText: String = ""
    @State private var collectionToDelete: GalleryCollection? = nil
    /// When the player exits a custom puzzle via the in-game back
    /// arrow / hamburger gallery row, GameState's
    /// `currentGalleryPuzzleId` is still set to the puzzle's id. On
    /// the next appear we scroll to that row and briefly tint its
    /// background so the player sees where they came back from.
    @State private var highlightedPuzzleId: String? = nil
    /// In-flight disk load. Held so a re-entrant reload (delete, then
    /// the swipe's own reload, then a dismissed Creator) cancels the
    /// older pass instead of racing it to the @State assignment.
    @State private var loadTask: Task<Void, Never>? = nil
    /// False until the first load lands. Gates the empty state so the
    /// gallery never claims to be empty before it has read the disk.
    @State private var didLoad = false

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollViewReader { proxy in
                Group {
                    if !didLoad {
                        // Deliberately blank rather than a spinner: the
                        // read normally finishes inside the sheet's own
                        // presentation animation, and a spinner that
                        // appears for two frames reads as a stutter.
                        Color.clear
                    } else if puzzles.isEmpty && favorites.isEmpty && collections.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
                .onChange(of: puzzles.map(\.id) + favorites.map(\.id)) { _, _ in
                    // Wait until the list has actual rows to scroll to
                    // — the menu-driven re-open path hits onAppear
                    // before reload() finishes, so we re-arm here.
                    focusReturnedPuzzleIfNeeded(proxy: proxy)
                }
                .onChange(of: communityEntries?.map(\.id) ?? []) { _, _ in
                    // Community plays focus the row in the inline
                    // section once the feed lands.
                    focusReturnedPuzzleIfNeeded(proxy: proxy)
                }
            }
            .kromaSheet(Strings.Menu.gallery) { dismiss() }
            .toolbar {
                // Creation sits beside the dismissal rather than opposite
                // it: "done" is navigation and always trailing, so a
                // content action that isn't a way out doesn't get the
                // leading slot where "back" belongs.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            openCreator()
                        } label: {
                            Label("New puzzle", systemImage: fullVersion.isUnlocked || fullVersion.canTry(.creator)
                                  ? "square.and.pencil" : "lock.fill")
                        }
                        Button {
                            collectionRenameTarget = nil
                            collectionNameText = ""
                            collectionAlertOpen = true
                        } label: {
                            Label("New collection", systemImage: "folder.badge.plus")
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
            .navigationDestination(for: GalleryCollection.self) { col in
                CollectionDetailView(game: game, started: $started, collection: col)
            }
        }
        .fullScreenCover(isPresented: $creatorOpen, onDismiss: { reload() }) {
            CreatorView(game: game, saveOnPlay: true)
        }
        .fullScreenCover(item: $editingPuzzle, onDismiss: { reload() }) { puzzle in
            CreatorView(game: game, saveOnPlay: false, editing: puzzle)
        }
        .sheet(isPresented: $fullVersionOpen) {
            FullVersionView(focus: .creator)
        }
        .sheet(item: $movingPuzzle, onDismiss: { reload() }) { puzzle in
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
        .onAppear {
            // If the player exited a puzzle launched from inside a
            // collection, restore the nav stack to that collection
            // so the back-arrow lands them where they started. The
            // CollectionDetailView itself handles the per-row scroll
            // + tint; we just push the right destination — once the
            // load has actually produced the collection list.
            reload(restoringNav: true)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .task {
            // One-shot community-feed pull on first appear so the
            // inline Community Puzzles section renders real rows
            // (or an empty-placeholder when the pool is still small).
            if communityEntries == nil {
                await refreshCommunityFeed()
            }
        }
    }

    /// Scroll to the row representing the just-played gallery puzzle
    /// and tint it for ~1.5s so the player visually re-acquires it.
    /// Consumes `game.currentGalleryPuzzleId` (clears it after) so a
    /// later re-open of the gallery doesn't re-trigger.
    private func focusReturnedPuzzleIfNeeded(proxy: ScrollViewProxy) {
        guard let id = game.currentGalleryPuzzleId else { return }
        // Skip when the puzzle was launched from inside a collection
        // — CollectionDetailView owns the focus in that case, and we
        // don't want to consume the id before it gets pushed.
        if game.currentGalleryCollectionId != nil { return }
        let inGallery = puzzles.contains(where: { $0.id == id })
                     || favorites.contains(where: { $0.id == id })
        let inCommunity = communityEntries?.contains(where: { $0.id == id }) ?? false
        guard inGallery || inCommunity else { return }
        game.currentGalleryPuzzleId = nil
        Task { @MainActor in
            // Tiny defer so the List has settled into its initial
            // layout before the scroll animates — without it scrollTo
            // can skip on first present.
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
                openCreator()
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
                            onEdit: { openCreator(editing: puzzle) }
                        )
                        .id(puzzle.id)
                        .listRowBackground(
                            highlightedPuzzleId == puzzle.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
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
                        .id(puzzle.id)
                        .listRowBackground(
                            highlightedPuzzleId == puzzle.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
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

            communitySection
        }
    }

    @ViewBuilder
    private var communitySection: some View {
        Section {
            // Sort toggle + status as the section's first row so it
            // sits inside the section card rather than pretending to
            // be a List header (List headers don't get tap targets
            // out of the box).
            HStack(spacing: 10) {
                Picker("Sort", selection: $communitySort) {
                    Text("Top").tag(CommunitySort.top)
                    Text("New").tag(CommunitySort.new)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                Spacer(minLength: 0)
                if communityEntries == nil {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button {
                        Task { await refreshCommunityFeed() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh community feed")
                }
            }
            .padding(.vertical, 2)
            .listRowSeparator(.hidden)
            .onChange(of: communitySort) { _, _ in
                Task { await refreshCommunityFeed() }
            }

            if let err = communityLoadError {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if communityEntries == nil {
                Text("Loading…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let list = communityEntries, list.isEmpty {
                Text("No community puzzles yet.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if let list = communityEntries {
                // id-based diffing so a Top↔New sort flip doesn't
                // re-key rows by position (which would attach each
                // row's per-row @State — voting flag, etc. — to the
                // wrong entry).
                ForEach(list, id: \.id) { entry in
                    let entryId = entry.id
                    CommunityGalleryRow(
                        entry: Binding(
                            get: {
                                communityEntries?.first(where: { $0.id == entryId })
                                    ?? entry
                            },
                            set: { newVal in
                                guard var arr = communityEntries,
                                      let i = arr.firstIndex(where: { $0.id == entryId })
                                else { return }
                                arr[i] = newVal
                                communityEntries = arr
                            }
                        ),
                        expanded: expandedCommunityId == entryId,
                        onToggleExpand: {
                            withAnimation(.spring(response: 0.32,
                                                   dampingFraction: 0.85)) {
                                if expandedCommunityId == entryId {
                                    expandedCommunityId = nil
                                } else {
                                    expandedCommunityId = entryId
                                }
                            }
                        },
                        onPlay: { playCommunityEntry(entry) }
                    )
                    .id(entryId)
                    .listRowBackground(
                        highlightedPuzzleId == entryId
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear
                    )
                }
            }
        } header: {
            Text("Community puzzles")
        }
    }

    /// Re-fetch the community feed under the current sort. Surfaces
    /// network errors as a small inline message rather than blanking
    /// the section so a momentary outage doesn't look like an empty
    /// pool.
    private func refreshCommunityFeed() async {
        let prev = communityEntries
        let (fetched, ok) = await CommunityStore.fetchFeed(
            sort: communitySort, limit: 50
        )
        await MainActor.run {
            if ok {
                communityEntries = fetched
                communityLoadError = nil
            } else {
                // Keep previous list visible if we had one; otherwise
                // surface an empty array so the placeholder shows.
                communityEntries = prev ?? []
                communityLoadError = "couldn't load community feed — check connection"
            }
        }
    }

    /// If the player just exited a puzzle launched from inside a
    /// collection, push that collection onto the nav stack so the
    /// back-arrow lands in the collection (not the gallery root).
    /// CollectionDetailView's onAppear focus handler does the
    /// per-row scroll + tint.
    private func restoreCollectionNavIfNeeded() {
        guard let cid = game.currentGalleryCollectionId else { return }
        guard let target = collections.first(where: { $0.id == cid }) else {
            // Collection was deleted while the puzzle was in flight.
            // Drop the stale ids so subsequent gallery interactions
            // (and the focus path) aren't blocked by them.
            game.currentGalleryCollectionId = nil
            game.currentGalleryPuzzleId = nil
            return
        }
        // Only push if we're not already there (avoids stacking on a
        // re-appear).
        if navPath.last?.id != target.id {
            navPath = [target]
        }
    }

    /// Everything the gallery list renders, assembled in one pass so
    /// the three stores can be read off the main thread together and
    /// applied as a single state update.
    private struct GalleryContents {
        let puzzles: [GalleryPuzzle]
        let favorites: [GalleryPuzzle]
        let collections: [GalleryCollection]
    }

    /// Re-read the three on-disk stores. Each entry is a separate JSON
    /// file that has to be read and decoded, so a gallery with a few
    /// dozen puzzles was a visible hitch when this ran inline on
    /// `onAppear`. The work moves to a background task and lands in one
    /// assignment; a newer call cancels the older one.
    ///
    /// `restoringNav` is set only by the appear path — the collection
    /// re-push has to wait for `collections` to be populated, or it
    /// would find no match and discard the ids that drive it.
    private func reload(restoringNav: Bool = false) {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            let loaded = await Task.detached(priority: .userInitiated) {
                GalleryContents(
                    puzzles: GalleryStore.all(),
                    favorites: FavoritesStore.all(),
                    collections: GalleryStore.collections()
                )
            }.value
            guard !Task.isCancelled else { return }
            puzzles = loaded.puzzles
            favorites = loaded.favorites
            collections = loaded.collections
            didLoad = true
            if restoringNav { restoreCollectionNavIfNeeded() }
            loadTask = nil
        }
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
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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
        let title = entry.doc.name ?? entry.submitterName
        // galleryPuzzleId carries the community entry's server id so
        // the back-arrow can scroll-and-tint the row in the inline
        // community section on return.
        game.loadCustomPuzzle(
            built,
            favoriteURL: nil,
            fromGallery: true,
            galleryPuzzleId: entry.id,
            title: title
        )
        started = true
        dismiss()
    }

    private func play(_ puzzle: GalleryPuzzle, favoriteURL: URL? = nil) {
        guard let built = CreatorCodec.rebuild(puzzle.doc) else { return }
        game.loadCustomPuzzle(
            built,
            favoriteURL: favoriteURL,
            fromGallery: true,
            galleryPuzzleId: puzzle.id,
            allowsFavorite: false,
            title: puzzle.doc.name
        )
        // Close gallery + drop into game. The dismiss chain routes
        // through the parent sheet's onDismiss; MenuView flips
        // `started` to true there.
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
            // Perfect-solve badge floats in the top-left corner when
            // the player has cleared this puzzle without burning a
            // heart or peeking the solution.
            HStack(spacing: 2) {
                let cells = puzzle.doc.gradients.first?.cells.prefix(5) ?? []
                ForEach(Array(cells.enumerated()), id: \.offset) { (_, cell) in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(OK.toColor(OKLCh(L: cell.L, c: cell.C, h: cell.h)))
                        .frame(width: 14, height: 30)
                }
            }
            .overlay(alignment: .topLeading) {
                if GallerySolvedStore.hasPerfected(puzzle.id) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                        .padding(2)
                        .background(
                            Circle().fill(Color.black.opacity(0.55))
                        )
                        .offset(x: -4, y: -4)
                        .accessibilityLabel("Perfect solve")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(puzzle.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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

/// Inline community row inside the Gallery list. Two states share
/// the same row:
///   • Compact: palette strip + submitter name + small vote summary.
///     A chevron hints that the row expands. The whole row is one
///     tap target — tap toggles expansion, never plays.
///   • Expanded: full-size up/down vote buttons (with optimistic
///     flip + server reconciliation) + a Play button. Play is the
///     only path into the actual puzzle.
struct CommunityGalleryRow: View {
    @Binding var entry: CommunityPuzzleEntry
    let expanded: Bool
    let onToggleExpand: () -> Void
    let onPlay: () -> Void
    @State private var voting: Bool = false

    private static let likeGreen  = Color(red: 0.36, green: 0.78, blue: 0.45)
    private static let dislikeRed = Color(red: 0.92, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            if expanded {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }
    }

    @ViewBuilder
    private var compactHeader: some View {
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
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("lv \(entry.level)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Label("\(entry.upCount)", systemImage: "arrowtriangle.up.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(entry.myVote == 1
                                     ? Self.likeGreen : Color.secondary)
                Label("\(entry.downCount)", systemImage: "arrowtriangle.down.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(entry.myVote == -1
                                     ? Self.dislikeRed : Color.secondary)
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        HStack(alignment: .center, spacing: 12) {
            voteArrow(direction: +1, color: Self.likeGreen,
                      system: "arrowtriangle.up.fill",
                      count: entry.upCount)
            voteArrow(direction: -1, color: Self.dislikeRed,
                      system: "arrowtriangle.down.fill",
                      count: entry.downCount)
            Spacer(minLength: 0)
            Button {
                onPlay()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { /* swallow — buttons handle their own taps */ }
    }

    @ViewBuilder
    private func voteArrow(direction: Int, color: Color,
                           system: String, count: Int) -> some View {
        let active = entry.myVote == direction
        Button {
            cast(direction)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: system)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(active ? color : Color.secondary)
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold,
                                   design: .rounded))
                    .foregroundStyle(active ? color : Color.secondary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                Capsule().fill(active
                                ? color.opacity(0.14)
                                : Color.gray.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .disabled(voting)
    }

    private var displayName: String {
        if let n = entry.submitterName, !n.isEmpty { return n }
        return "Untitled"
    }

    /// Cast or retract a vote (tap-same retracts). Optimistic flip
    /// updates the binding immediately; server response overwrites,
    /// failure rolls back to the captured snapshot.
    private func cast(_ direction: Int) {
        let next = entry.myVote == direction ? 0 : direction
        let prior = entry
        applyOptimistic(next)
        voting = true
        Task {
            let result = await CommunityStore.vote(
                puzzleId: entry.id, vote: next
            )
            await MainActor.run {
                voting = false
                switch result {
                case .success(let resp):
                    if let up = resp.upCount { entry.upCount = up }
                    if let down = resp.downCount { entry.downCount = down }
                    if let score = resp.score { entry.score = score }
                    entry.myVote = resp.myVote ?? next
                case .failure:
                    entry = prior
                }
            }
        }
    }

    private func applyOptimistic(_ next: Int) {
        let prev = entry.myVote
        if prev == next { return }
        if prev == 1 { entry.upCount = max(0, entry.upCount - 1) }
        if prev == -1 { entry.downCount = max(0, entry.downCount - 1) }
        if next == 1 { entry.upCount += 1 }
        if next == -1 { entry.downCount += 1 }
        entry.myVote = next
        entry.score = entry.upCount - entry.downCount
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
