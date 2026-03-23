import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Joke> { $0.isDeleted == true }, sort: \Joke.deletedDate, order: .reverse)
    private var trashedJokes: [Joke]

    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false

    private var filteredTrash: [Joke] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trashedJokes }
        let lower = trimmed.lowercased()
        return trashedJokes.filter {
            $0.title.lowercased().contains(lower) ||
            $0.content.lowercased().contains(lower)
        }
    }

    var body: some View {
        Group {
            if filteredTrash.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Trash is Empty",
                    subtitle: "Deleted jokes appear here until you empty trash."
                )
            } else {
                List {
                    ForEach(filteredTrash) { joke in
                        NavigationLink(destination: JokeDetailView(joke: joke)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                                    .font(.headline)
                                Text(joke.content)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                if let deletedDate = joke.deletedDate {
                                    Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(joke)
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                joke.restoreFromTrash()
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(AppTheme.Colors.success)
                        }
                        .contextMenu {
                            Button {
                                joke.restoreFromTrash()
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                modelContext.delete(joke)
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Trash")
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
        .alert("Empty Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                for joke in trashedJokes {
                    modelContext.delete(joke)
                }
            }
        } message: {
            Text("This permanently deletes all jokes in trash.")
        }
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
    .modelContainer(for: Joke.self, inMemory: true)
}
