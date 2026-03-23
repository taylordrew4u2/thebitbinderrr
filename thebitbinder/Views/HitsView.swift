//
//  HitsView.swift
//  thebitbinder
//
//  Dedicated folder view showing only jokes marked as "Hits"
//

import SwiftUI
import SwiftData

struct HitsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    @AppStorage("roastModeEnabled") private var roastMode = false
    @Query(sort: \Joke.dateCreated, order: .reverse)
    private var allJokes: [Joke]
    
    @State private var searchText = ""
    
    private var hitJokes: [Joke] {
        allJokes.filter { $0.isHit && !$0.isDeleted }
    }
    
    private var filteredHits: [Joke] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return hitJokes }
        let lower = trimmed.lowercased()
        return hitJokes.filter {
            $0.content.lowercased().contains(lower) ||
            $0.title.lowercased().contains(lower)
        }
    }
    
    var body: some View {
        Group {
            if filteredHits.isEmpty {
                BitBinderEmptyState(
                    icon: roastMode ? "flame" : "star.fill",
                    title: roastMode ? "No Fire Hits Yet" : "No Hits Yet",
                    subtitle: "Mark your best jokes as Hits and they'll appear here — your perfected material, ready to perform.",
                    roastMode: roastMode,
                    iconGradient: roastMode
                        ? AppTheme.Colors.roastEmberGradient
                        : LinearGradient(
                            colors: [AppTheme.Colors.hitsGold, AppTheme.Colors.hitsGoldLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(filteredHits) { joke in
                            NavigationLink(destination: JokeDetailView(joke: joke)) {
                                JokeCardView(joke: joke, roastMode: roastMode)
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .contextMenu {
                                Button {
                                    joke.isHit = false
                                    joke.dateModified = Date()
                                } label: {
                                    Label("Remove from Hits", systemImage: "star.slash")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    joke.moveToTrash()
                                } label: {
                                    Label("Move to Trash", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
        .navigationTitle(roastMode ? "🔥 The Hits" : "⭐ The Hits")
        .navigationBarTitleDisplayMode(.large)
        .bitBinderToolbar(roastMode: roastMode)
        .searchable(text: $searchText, prompt: "Search hits")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { expandAllJokes.toggle() }) {
                    Label(expandAllJokes ? "Collapse" : "Expand", systemImage: expandAllJokes ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                }
                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
            }
        }
        .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
    }
}

#Preview {
    NavigationStack {
        HitsView()
    }
    .modelContainer(for: Joke.self, inMemory: true)
}
