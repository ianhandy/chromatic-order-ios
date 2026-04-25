//  Dev-only moderation surface for the community pool. Lets the
//  developer paste an admin token, pull the live Pending + Approved
//  feeds from kroma.ianhandy.com, preview each puzzle, and approve /
//  reject rows. Reject on an approved row removes it from the public
//  feed (status flipped to 'rejected' server-side).
//
//  Entire view is wrapped in `#if DEBUG` at the call site so it ships
//  out of Release builds.

import SwiftUI

struct DevSheet: View {
    @Bindable var game: GameState
    @Environment(\.dismiss) private var dismiss

    @State private var token: String =
        UserDefaults.standard.string(forKey: CommunityStore.adminTokenKey) ?? ""
    @State private var pending: [CommunityPuzzleEntry] = []
    @State private var approved: [CommunityPuzzleEntry] = []
    @State private var loadingPending: Bool = false
    @State private var loadingApproved: Bool = false
    @State private var pendingError: String? = nil
    @State private var approvedError: String? = nil
    /// id of a row currently in flight (approve/reject) so the row
    /// can disable its buttons + show a spinner.
    @State private var actingId: String? = nil
    /// One-line status message rendered under the title bar — soaks
    /// up "rejected", "approved", or transient error copy without
    /// requiring an alert sheet.
    @State private var status: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                tokenSection
                Section {
                    Button("Reload feeds") { reloadAll() }
                        .disabled(loadingPending || loadingApproved)
                    if let status {
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Actions")
                }

                Section {
                    if loadingPending && pending.isEmpty {
                        ProgressView()
                    } else if let pendingError {
                        Text(pendingError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    } else if pending.isEmpty {
                        Text("Queue is empty.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pending) { entry in
                            DevPuzzleRow(
                                entry: entry,
                                statusTag: "pending",
                                busy: actingId == entry.id,
                                onPlay: { play(entry) },
                                onApprove: { moderate(entry, action: .approve) },
                                onReject: { moderate(entry, action: .reject) }
                            )
                        }
                    }
                } header: {
                    Text("Pending (\(pending.count))")
                }

                Section {
                    if loadingApproved && approved.isEmpty {
                        ProgressView()
                    } else if let approvedError {
                        Text(approvedError)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    } else if approved.isEmpty {
                        Text("No approved community puzzles.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(approved) { entry in
                            DevPuzzleRow(
                                entry: entry,
                                statusTag: "approved",
                                busy: actingId == entry.id,
                                onPlay: { play(entry) },
                                onApprove: nil,
                                onReject: { moderate(entry, action: .reject) }
                            )
                        }
                    }
                } header: {
                    Text("Approved (\(approved.count))")
                } footer: {
                    Text("Reject on an approved puzzle pulls it from the public feed.")
                }
            }
            .navigationTitle("Dev — Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { reloadAll() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Token section

    @ViewBuilder
    private var tokenSection: some View {
        Section {
            TextField("DAILY_ADMIN_TOKEN", text: $token, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...4)
            HStack {
                Button("Save token") {
                    UserDefaults.standard.set(
                        token.trimmingCharacters(in: .whitespacesAndNewlines),
                        forKey: CommunityStore.adminTokenKey)
                    status = "Token saved."
                    reloadAll()
                }
                Spacer()
                Button(role: .destructive) {
                    token = ""
                    UserDefaults.standard.removeObject(forKey: CommunityStore.adminTokenKey)
                    pending = []; approved = []
                    status = "Token cleared."
                } label: {
                    Text("Forget")
                }
            }
        } header: {
            Text("Admin token")
        } footer: {
            Text("Same string the web admin UI stores under kroma.dailyAdminToken. Required for pending + moderate.")
        }
    }

    // MARK: - Behavior

    private func reloadAll() {
        loadPending()
        loadApproved()
    }

    private func loadPending() {
        loadingPending = true; pendingError = nil
        Task {
            let result = await CommunityStore.adminFetchPending(limit: 100)
            await MainActor.run {
                loadingPending = false
                switch result {
                case .success(let rows): pending = rows
                case .failure(let err):
                    pendingError = err.localizedDescription
                }
            }
        }
    }

    private func loadApproved() {
        loadingApproved = true; approvedError = nil
        Task {
            // Public feed — newest first so the dev menu reflects the
            // ordering moderators care about (recent additions first).
            let (entries, ok) = await CommunityStore.fetchFeed(sort: .new, limit: 100)
            await MainActor.run {
                loadingApproved = false
                if ok {
                    approved = entries
                } else {
                    approvedError = "feed unavailable"
                }
            }
        }
    }

    private func moderate(_ entry: CommunityPuzzleEntry, action: CommunityStore.AdminAction) {
        actingId = entry.id
        status = nil
        Task {
            let result = await CommunityStore.adminModerate(id: entry.id, action: action)
            await MainActor.run {
                actingId = nil
                switch result {
                case .success(let resp):
                    let label = resp.status ?? action.rawValue
                    status = "\(action.rawValue) → \(label)"
                    // Move the row out of its current bucket. Approve
                    // pulls from pending → approved; reject removes
                    // from whichever bucket it was in.
                    pending.removeAll { $0.id == entry.id }
                    if action == .approve {
                        // Re-fetch approved so the row appears with
                        // its server-assigned approved_at timestamp +
                        // ordering, instead of trying to splice it
                        // locally.
                        loadApproved()
                    } else {
                        approved.removeAll { $0.id == entry.id }
                    }
                case .failure(let err):
                    status = "\(action.rawValue) failed: \(err.localizedDescription)"
                }
            }
        }
    }

    private func play(_ entry: CommunityPuzzleEntry) {
        guard let puzzle = CreatorCodec.rebuild(entry.doc, level: entry.level) else { return }
        let title = entry.doc.name ?? entry.submitterName
        game.loadCustomPuzzle(puzzle, title: title)
        dismiss()
    }
}

// MARK: - Row

private struct DevPuzzleRow: View {
    let entry: CommunityPuzzleEntry
    let statusTag: String
    let busy: Bool
    let onPlay: () -> Void
    let onApprove: (() -> Void)?
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                thumb
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("id: \(entry.id.prefix(10))…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(action: onPlay) { Text("Play") }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                if let onApprove {
                    Button(action: onApprove) { Text("Approve") }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                }
                Button(role: .destructive, action: onReject) {
                    Text(statusTag == "approved" ? "Remove" : "Reject")
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                if busy {
                    ProgressView().scaleEffect(0.8)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var displayTitle: String {
        if let n = entry.doc.name, !n.isEmpty { return n }
        if let n = entry.submitterName, !n.isEmpty { return n }
        return "lv \(entry.level) · diff \(entry.doc.difficulty ?? 0)/10"
    }

    private var subtitle: String {
        let dim = "\(entry.doc.gridW)×\(entry.doc.gridH)"
        let votes = "▲\(entry.upCount) ▼\(entry.downCount)"
        return "lv \(entry.level) · \(dim) · \(votes)"
    }

    @ViewBuilder
    private var thumb: some View {
        if let puzzle = CreatorCodec.rebuild(entry.doc, level: entry.level),
           let img = PuzzlePreviewRenderer.render(puzzle) {
            img
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 54, height: 54)
        }
    }
}
