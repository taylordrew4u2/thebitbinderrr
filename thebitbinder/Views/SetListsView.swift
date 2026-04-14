//
//  SetListsView.swift
//  thebitbinder
//
//  Set lists view using standard iOS patterns.
//

import SwiftUI
import SwiftData

struct SetListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<SetList> { !$0.isDeleted }) private var setLists: [SetList]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var showingCreateSetList = false
    @State private var showingTrash = false
    @State private var showingRecording = false
    @State private var searchText = ""
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    
    var filteredSetLists: [SetList] {
        let sorted = setLists.sorted { $0.dateModified > $1.dateModified }
        if searchText.isEmpty {
            return sorted
        }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        Group {
            if filteredSetLists.isEmpty && searchText.isEmpty {
                BitBinderEmptyState(
                    icon: "list.bullet.rectangle.portrait",
                    title: roastMode ? "No Roast Sets Yet" : "No Sets Yet",
                    subtitle: "Create a set to organize jokes for your performances",
                    actionTitle: "Create Set",
                    action: { showingCreateSetList = true },
                    roastMode: roastMode
                )
            } else {
                List {
                    ForEach(filteredSetLists) { setList in
                        NavigationLink(value: setList) {
                            SetListRowView(setList: setList)
                        }
                    }
                    .onDelete(perform: deleteSetLists)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationDestination(for: SetList.self) { setList in
            SetListDetailView(setList: setList)
        }
        .searchable(text: $searchText, prompt: roastMode ? "Search roast sets" : "Search sets")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateSetList = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingRecording = true
                    } label: {
                        Label("Record Performance", systemImage: "record.circle")
                    }
                    
                    Section {
                        Button {
                            showingTrash = true
                        } label: {
                            Label("Trash", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            SetListTrashView()
        }
        .sheet(isPresented: $showingCreateSetList) {
            CreateSetListView()
        }
        .sheet(isPresented: $showingRecording) {
            StandaloneRecordingView()
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }
    
    private func deleteSetLists(at offsets: IndexSet) {
        for index in offsets {
            filteredSetLists[index].moveToTrash()
        }
        do {
            try modelContext.save()
        } catch {
            print("[SetListsView] Failed to save after soft-delete: \(error)")
            persistenceError = "Could not delete set list: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }
}

struct SetListRowView: View {
    let setList: SetList
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    private var jokeCount: Int {
        roastMode ? setList.roastJokeIDs.count : setList.jokeIDs.count
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(setList.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if setList.isFinalized {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                Text("\(jokeCount) \(roastMode ? "roasts" : "jokes")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(setList.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SetListsView()
            .navigationTitle("Sets")
    }
    .modelContainer(for: SetList.self, inMemory: true)
}