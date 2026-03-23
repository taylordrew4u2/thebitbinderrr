//
//  SetListTrashView.swift
//  thebitbinder
//
//  Trash bin for soft-deleted set lists.
//  Restore puts the set list back in the active list.
//  "Delete Forever" permanently removes the record from the store.
//

import SwiftUI
import SwiftData

struct SetListTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Query(
        filter: #Predicate<SetList> { $0.isDeleted == true },
        sort: \SetList.deletedDate,
        order: .reverse
    ) private var trashedSetLists: [SetList]

    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false

    private var filtered: [SetList] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return trashedSetLists }
        return trashedSetLists.filter { $0.name.lowercased().contains(t) }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Set List Trash is Empty",
                    subtitle: "Deleted set lists appear here for 30 days before being permanently removed.",
                    roastMode: roastMode
                )
            } else {
                List {
                    ForEach(filtered) { setList in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(setList.name)
                                .font(.headline)
                            HStack(spacing: 8) {
                                Text("\(setList.totalItemCount) item\(setList.totalItemCount == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let deletedDate = setList.deletedDate {
                                    Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(setList)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [SetListTrashView] Failed to permanently delete set list: \(error)")
                                }
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                setList.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [SetListTrashView] Failed to restore set list: \(error)")
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AppTheme.Colors.success)
                        }
                        .contextMenu {
                            Button {
                                setList.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [SetListTrashView] Failed to restore set list: \(error)")
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                modelContext.delete(setList)
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("❌ [SetListTrashView] Failed to permanently delete set list: \(error)")
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
        .navigationTitle(roastMode ? "🔥 Set List Trash" : "Set List Trash")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search trash")
        .toolbar {
            if !trashedSetLists.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingEmptyTrashAlert = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("Empty Set List Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                for setList in trashedSetLists {
                    modelContext.delete(setList)
                }
                do {
                    try modelContext.save()
                } catch {
                    print("❌ [SetListTrashView] Failed to save after empty trash: \(error)")
                }
            }
        } message: {
            Text("This permanently deletes all \(trashedSetLists.count) set list\(trashedSetLists.count == 1 ? "" : "s"). This cannot be undone.")
        }
    }
}

#Preview {
    NavigationStack {
        SetListTrashView()
    }
    .modelContainer(for: SetList.self, inMemory: true)
}
