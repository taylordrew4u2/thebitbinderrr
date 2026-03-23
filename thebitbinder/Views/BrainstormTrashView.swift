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
    @Query(
        filter: #Predicate<BrainstormIdea> { $0.isDeleted == true },
        sort: \BrainstormIdea.deletedDate,
        order: .reverse
    ) private var trashedIdeas: [BrainstormIdea]

    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false

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
                            Text(idea.content)
                                .font(.subheadline)
                                .lineLimit(3)
                            if let deletedDate = idea.deletedDate {
                                Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(idea)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [BrainstormTrashView] Failed to permanently delete idea: \(error)")
                                }
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                idea.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [BrainstormTrashView] Failed to restore idea: \(error)")
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AppTheme.Colors.success)
                        }
                        .contextMenu {
                            Button {
                                idea.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [BrainstormTrashView] Failed to restore idea: \(error)")
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                modelContext.delete(idea)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [BrainstormTrashView] Failed to permanently delete idea: \(error)")
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
        .navigationTitle(roastMode ? "🔥 Thought Trash" : "Thought Trash")
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
        .alert("Empty Thought Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                for idea in trashedIdeas {
                    modelContext.delete(idea)
                }
                do {
                    try modelContext.save()
                } catch {
                    print("❌ [BrainstormTrashView] Failed to save after empty trash: \(error)")
                }
            }
        } message: {
            Text("This permanently deletes all \(trashedIdeas.count) thought\(trashedIdeas.count == 1 ? "" : "s"). This cannot be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        BrainstormTrashView()
    }
    .modelContainer(for: BrainstormIdea.self, inMemory: true)
}
