//
//  BrainstormTrashView.swift
//  thebitbinder
//
//  Trash bin for soft-deleted brainstorm ideas.
//  Restore puts the idea back in the active grid.
//  "Delete Forever" permanently removes the record from the store.
//

import SwiftUI
import SwiftData

struct BrainstormTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("showFullContent") private var showFullContent = true
    @Query(
        filter: #Predicate<BrainstormIdea> { $0.isDeleted == true },
        sort: \BrainstormIdea.deletedDate,
        order: .reverse
    ) private var trashedIdeas: [BrainstormIdea]

    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false
    @State private var ideaToDelete: BrainstormIdea?
    @State private var showingDeleteOneAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false

    private var filtered: [BrainstormIdea] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return trashedIdeas }
        return trashedIdeas.filter { $0.content.lowercased().contains(t) }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Thought Trash is Empty",
                    subtitle: "Deleted thoughts appear here for 30 days before being permanently removed.",
                    roastMode: roastMode
                )
            } else {
                List {
                    ForEach(filtered) { idea in
                        VStack(alignment: .leading, spacing: 6) {
                            if showFullContent {
                                Text(idea.content)
                                    .font(.subheadline)
                            } else {
                                Text(idea.content.components(separatedBy: .newlines).first ?? idea.content)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            if let deletedDate = idea.deletedDate {
                                Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                ideaToDelete = idea
                                showingDeleteOneAlert = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                restoreIdea(idea)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                restoreIdea(idea)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                ideaToDelete = idea
                                showingDeleteOneAlert = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search trash")
        .toolbar {
            if !trashedIdeas.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingEmptyTrashAlert = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("Delete Forever?", isPresented: $showingDeleteOneAlert) {
            Button("Cancel", role: .cancel) { ideaToDelete = nil }
            Button("Delete", role: .destructive) {
                if let idea = ideaToDelete {
                    permanentlyDelete(idea)
                    ideaToDelete = nil
                }
            }
        } message: {
            Text("This thought will be permanently deleted. This cannot be undone.")
        }
        .alert("Empty Thought Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently deletes all \(trashedIdeas.count) thought\(trashedIdeas.count == 1 ? "" : "s"). This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    // MARK: - Actions

    private func restoreIdea(_ idea: BrainstormIdea) {
        idea.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormTrashView] Failed to restore: \(error)")
            persistenceError = "Could not restore thought: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func permanentlyDelete(_ idea: BrainstormIdea) {
        modelContext.delete(idea)
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormTrashView] Failed to delete: \(error)")
            persistenceError = "Could not delete thought: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func emptyTrash() {
        for idea in trashedIdeas {
            modelContext.delete(idea)
        }
        do {
            try modelContext.save()
        } catch {
            print(" [BrainstormTrashView] Failed to empty trash: \(error)")
            persistenceError = "Could not empty trash: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        BrainstormTrashView()
    }
    .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
