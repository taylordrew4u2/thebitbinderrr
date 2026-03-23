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
    @Query private var folders: [JokeFolder]
    @AppStorage("roastModeEnabled") private var roastMode = false
    
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
        NavigationView {
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
                                .font(.system(size: 60))
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
                                        Text(joke.content)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if selectedJokeIDs.contains(joke.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppTheme.Colors.primaryAction)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .background(roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
            .navigationTitle(roastMode ? "🔥 Add Jokes" : "Add Jokes")
            .navigationBarTitleDisplayMode(.inline)
            .bitBinderToolbar(roastMode: roastMode)
            .searchable(text: $searchText, prompt: "Search jokes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedJokeIDs.count))") {
                        addJokes()
                    }
                    .disabled(selectedJokeIDs.isEmpty)
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                }
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
    }
    
    private func addJokes() {
        setList.jokeIDs.append(contentsOf: selectedJokeIDs)
        setList.dateModified = Date()
        dismiss()
    }
}
