//
//  RoastJokeTrashView.swift
//  thebitbinder
//
//  Trash bin for soft-deleted roast jokes belonging to a specific RoastTarget.
//  Restore puts the joke back in the active list for that target.
//  "Delete Forever" permanently removes the record from the store.
//

import SwiftUI
import SwiftData

struct RoastJokeTrashView: View {
    @Environment(\.modelContext) private var modelContext
    let target: RoastTarget

    @AppStorage("showFullContent") private var showFullContent = true
    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false
    @State private var jokeToDelete: RoastJoke?
    @State private var showingDeleteOneAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false
    
    /// Safe access to target name
    private var safeTargetName: String {
        target.isValid ? target.name : "Target"
    }

    private var trashedJokes: [RoastJoke] {
        // Safety check - return empty if target is invalid
        guard target.isValid, let jokes = target.jokes else { return [] }
        return jokes
            .filter { $0.isDeleted }
            .sorted { ($0.deletedDate ?? .distantPast) > ($1.deletedDate ?? .distantPast) }
    }

    private var filtered: [RoastJoke] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return trashedJokes }
        return trashedJokes.filter { $0.content.lowercased().contains(t) }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Roast Trash is Empty",
                    subtitle: "Deleted roasts for \(safeTargetName) appear here for 30 days before being permanently removed.",
                    roastMode: true
                )
            } else {
                List {
                    ForEach(filtered) { joke in
                        VStack(alignment: .leading, spacing: 6) {
                            if !joke.title.isEmpty {
                                Text(joke.title)
                                    .font(.headline)
                            }
                            if showFullContent {
                                Text(joke.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if joke.title.isEmpty {
                                Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            if let deletedDate = joke.deletedDate {
                                Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                jokeToDelete = joke
                                showingDeleteOneAlert = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                restoreJoke(joke)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                restoreJoke(joke)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                jokeToDelete = joke
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
            if !trashedJokes.isEmpty {
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
            Button("Cancel", role: .cancel) { jokeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let joke = jokeToDelete {
                    permanentlyDelete(joke)
                    jokeToDelete = nil
                }
            }
        } message: {
            Text("This roast will be permanently deleted. This cannot be undone.")
        }
        .alert("Empty Roast Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently deletes all \(trashedJokes.count) trashed roast\(trashedJokes.count == 1 ? "" : "s") for \(safeTargetName). This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    // MARK: - Actions

    private func restoreJoke(_ joke: RoastJoke) {
        joke.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [RoastJokeTrashView] Failed to restore: \(error)")
            persistenceError = "Could not restore roast: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func permanentlyDelete(_ joke: RoastJoke) {
        modelContext.delete(joke)
        do {
            try modelContext.save()
        } catch {
            print(" [RoastJokeTrashView] Failed to delete: \(error)")
            persistenceError = "Could not delete roast: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func emptyTrash() {
        for joke in trashedJokes {
            modelContext.delete(joke)
        }
        do {
            try modelContext.save()
        } catch {
            print(" [RoastJokeTrashView] Failed to empty trash: \(error)")
            persistenceError = "Could not empty trash: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}
