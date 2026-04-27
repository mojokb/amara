import SwiftUI

/// Left panel showing the git worktree list.
struct WorktreeListView: View {
    let worktrees: [WorktreeEntry]
    let selectedPath: String?
    let isLoading: Bool
    let error: String?
    /// Paths of worktrees that have at least one agent with new activity.
    let needsAttentionPaths: Set<String>
    let onSelect: (WorktreeEntry) -> Void
    let onRefresh: () -> Void
    let onCreateWorktree: (String) async throws -> Void
    /// Called when a file is tapped in the file browser. Args: (fileURL, worktreePath).
    let onOpenFile: (URL, String) -> Void

    @State private var showingCreateSheet = false
    @State private var newBranch = ""
    @State private var createError: String?
    @State private var isCreating = false

    /// Non-nil while the file browser panel is shown for a worktree.
    @State private var fileBrowserEntry: WorktreeEntry? = nil

    var body: some View {
        ZStack {
            // Worktree list (slides left when file browser opens)
            listPanel
                .offset(x: fileBrowserEntry == nil ? 0 : -20)
                .opacity(fileBrowserEntry == nil ? 1 : 0)

            // File browser panel (slides in from the right)
            if let entry = fileBrowserEntry {
                fileBrowserPanel(for: entry)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: fileBrowserEntry?.path)
        .sheet(isPresented: $showingCreateSheet) {
            createSheet
        }
    }

    // MARK: - List panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                errorView(error)
            } else if worktrees.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("WORKTREES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button(action: { showingCreateSheet = true }) {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(worktrees) { worktree in
                    WorktreeRowView(
                        worktree: worktree,
                        isSelected: worktree.path == selectedPath,
                        needsAttention: needsAttentionPaths.contains(worktree.path)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        guard !worktree.isBare else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            fileBrowserEntry = worktree
                        }
                    }
                    .onTapGesture(count: 1) {
                        if !worktree.isBare { onSelect(worktree) }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - File browser panel

    private func fileBrowserPanel(for entry: WorktreeEntry) -> some View {
        VStack(spacing: 0) {
            // Header: back button + worktree name
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        fileBrowserEntry = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(entry.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            WorktreeFileBrowser(rootPath: entry.path) { url in
                onOpenFile(url, entry.path)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Create sheet

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Worktree")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Branch name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("feature/my-branch", text: $newBranch)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitCreate() }
            }

            if let err = createError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismissCreate() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { submitCreate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newBranch.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func submitCreate() {
        let branch = newBranch.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return }
        isCreating = true
        createError = nil
        Task {
            do {
                try await onCreateWorktree(branch)
                dismissCreate()
            } catch {
                createError = error.localizedDescription
            }
            isCreating = false
        }
    }

    private func dismissCreate() {
        showingCreateSheet = false
        newBranch = ""
        createError = nil
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No worktrees found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct WorktreeRowView: View {
    let worktree: WorktreeEntry
    let isSelected: Bool
    let needsAttention: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Text(worktree.branch)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if needsAttention {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
            } else if worktree.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
        .opacity(worktree.isBare ? 0.4 : 1.0)
    }
}
