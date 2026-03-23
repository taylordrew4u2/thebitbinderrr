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

    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false

    private var trashedJokes: [RoastJoke] {
        (target.jokes ?? [])
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
                    subtitle: "Deleted roasts for \(target.name) appear here for 30 days before being permanently removed.",
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
                            Text(joke.content)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            if let deletedDate = joke.deletedDate {
                                Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(joke)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [RoastJokeTrashView] Failed to permanently delete roast joke: \(error)")
                                }
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                joke.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [RoastJokeTrashView] Failed to restore roast joke: \(error)")
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AppTheme.Colors.success)
                        }
                        .contextMenu {
                            Button {
                                joke.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [RoastJokeTrashView] Failed to restore roast joke: \(error)")
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                modelContext.delete(joke)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [RoastJokeTrashView] Failed to permanently delete roast joke: \(error)")
                                }
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Roast Trash")
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
        .alert("Empty Roast Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                for joke in trashedJokes {
                    modelContext.delete(joke)
                }
                do {
                    try modelContext.save()
                } catch {
                    print("❌ [RoastJokeTrashView] Failed to save after empty trash: \(error)")
                }
            }
        } message: {
            Text("This permanently deletes all \(trashedJokes.count) trashed roast\(trashedJokes.count == 1 ? "" : "s") for \(target.name). This cannot be undone.")
        }
    }
}
