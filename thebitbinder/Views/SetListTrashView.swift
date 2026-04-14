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
    @State private var setListToDelete: SetList?
    @State private var showingDeleteOneAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false

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
                                setListToDelete = setList
                                showingDeleteOneAlert = true
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                restoreSetList(setList)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                restoreSetList(setList)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                setListToDelete = setList
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
        .alert("Delete Forever?", isPresented: $showingDeleteOneAlert) {
            Button("Cancel", role: .cancel) { setListToDelete = nil }
            Button("Delete", role: .destructive) {
                if let setList = setListToDelete {
                    permanentlyDelete(setList)
                    setListToDelete = nil
                }
            }
        } message: {
            Text("This set list will be permanently deleted. This cannot be undone.")
        }
        .alert("Empty Set List Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently deletes all \(trashedSetLists.count) set list\(trashedSetLists.count == 1 ? "" : "s"). This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    // MARK: - Actions

    private func restoreSetList(_ setList: SetList) {
        setList.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [SetListTrashView] Failed to restore: \(error)")
            persistenceError = "Could not restore set list: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func permanentlyDelete(_ setList: SetList) {
        modelContext.delete(setList)
        do {
            try modelContext.save()
        } catch {
            print(" [SetListTrashView] Failed to delete: \(error)")
            persistenceError = "Could not delete set list: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func emptyTrash() {
        for setList in trashedSetLists {
            modelContext.delete(setList)
        }
        do {
            try modelContext.save()
        } catch {
            print(" [SetListTrashView] Failed to empty trash: \(error)")
            persistenceError = "Could not empty trash: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        SetListTrashView()
    }
    .modelContainer(for: SetList.self, inMemory: true)
}
