//
//  AddJokesToSetListView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct AddJokesToSetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var jokes: [Joke]
    @Query(filter: #Predicate<JokeFolder> { !$0.isDeleted }) private var folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("showFullContent") private var showFullContent = true
    
    @Bindable var setList: SetList
    var currentJokeIDs: [UUID]
    
    @State private var selectedJokeIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var selectedFolder: JokeFolder? = nil
    
    var availableJokes: [Joke] {
        // Start with jokes not already in the set list
        var base = jokes.filter { joke in
            !currentJokeIDs.contains(joke.id)
        }
        // If a folder is selected, filter into that folder
        if let folder = selectedFolder {
            base = base.filter { $0.folder?.id == folder.id }
        }
        // Apply search if present
        if searchText.isEmpty { return base }
        let lower = searchText.lowercased()
        return base.filter { j in
            j.title.lowercased().contains(lower) || j.content.lowercased().contains(lower)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Folder selection chips
                if !folders.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // All jokes chip
                            FolderChip(
                                name: "All Jokes",
                                isSelected: selectedFolder == nil,
                                action: { selectedFolder = nil }
                            )
                            ForEach(folders) { folder in
                                FolderChip(
                                    name: folder.name,
                                    isSelected: selectedFolder?.id == folder.id,
                                    action: { selectedFolder = folder }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground))
                    Divider()
                }

                Group {
                    if availableJokes.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "text.bubble")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("No jokes available")
                                .font(.title3)
                                .foregroundColor(.gray)
                            Text("All your jokes are already in this set list")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        List(availableJokes) { joke in
                            Button(action: {
                                if selectedJokeIDs.contains(joke.id) {
                                    selectedJokeIDs.remove(joke.id)
                                } else {
                                    selectedJokeIDs.insert(joke.id)
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(joke.title)
                                            .font(.headline)
                                        if showFullContent {
                                            Text(joke.content)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if selectedJokeIDs.contains(joke.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .background(roastMode ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .searchable(text: $searchText, prompt: "Search jokes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedJokeIDs.count))") {
                        addJokes()
                    }
                    .disabled(selectedJokeIDs.isEmpty)
                    .foregroundColor(.blue)
                }
            }
        }
        .tint(.blue)
    }
    
    private func addJokes() {
        setList.jokeIDs.append(contentsOf: selectedJokeIDs)
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [AddJokesToSetListView] Failed to save added jokes: \(error)")
            #endif
        }
        dismiss()
    }
}