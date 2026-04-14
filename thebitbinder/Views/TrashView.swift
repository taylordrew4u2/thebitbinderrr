import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Joke> { $0.isDeleted == true }, sort: \Joke.dateModified, order: .reverse)
    private var trashedJokes: [Joke]
    
    @Query(filter: #Predicate<RoastJoke> { $0.isDeleted == true }, sort: \RoastJoke.dateModified, order: .reverse)
    private var trashedRoastJokes: [RoastJoke]

    @AppStorage("showFullContent") private var showFullContent = true
    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false
    @State private var jokeToDelete: Joke?
    @State private var roastJokeToDelete: RoastJoke?
    @State private var showingDeleteOneAlert = false
    @State private var showingDeleteRoastAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false
    
    // Debug: log counts on appear
    private func logTrashCounts() {
        #if DEBUG
        print(" [TrashView] Jokes in trash: \(trashedJokes.count)")
        print(" [TrashView] Roasts in trash: \(trashedRoastJokes.count)")
        for roast in trashedRoastJokes {
            print("   - Roast: \(roast.content.prefix(30))... deleted: \(roast.deletedDate?.description ?? "nil")")
        }
        #endif
    }

    private var filteredJokes: [Joke] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trashedJokes }
        let lower = trimmed.lowercased()
        return trashedJokes.filter {
            $0.title.lowercased().contains(lower) ||
            $0.content.lowercased().contains(lower)
        }
    }
    
    private var filteredRoastJokes: [RoastJoke] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trashedRoastJokes }
        let lower = trimmed.lowercased()
        return trashedRoastJokes.filter {
            $0.content.lowercased().contains(lower) ||
            ($0.target?.name.lowercased().contains(lower) ?? false)
        }
    }
    
    private var totalTrashedCount: Int {
        trashedJokes.count + trashedRoastJokes.count
    }
    
    private var isTrashEmpty: Bool {
        filteredJokes.isEmpty && filteredRoastJokes.isEmpty
    }

    var body: some View {
        Group {
            if isTrashEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Trash is Empty",
                    subtitle: "Deleted jokes and roasts appear here until you empty trash."
                )
            } else {
                List {
                    // Regular Jokes Section
                    if !filteredJokes.isEmpty {
                        Section {
                            ForEach(filteredJokes) { joke in
                                NavigationLink(destination: JokeDetailView(joke: joke)) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                                            .font(.headline)
                                        if showFullContent {
                                            Text(joke.content)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
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
                        } header: {
                            HStack {
                                Image(systemName: "text.quote")
                                Text("Jokes (\(filteredJokes.count))")
                            }
                        }
                    }
                    
                    // Roast Jokes Section
                    if !filteredRoastJokes.isEmpty {
                        Section {
                            ForEach(filteredRoastJokes) { roast in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "flame.fill")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        if let targetName = roast.target?.name {
                                            Text(targetName)
                                                .font(.caption.bold())
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    
                                    if showFullContent {
                                        Text(roast.content)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text(roast.content.components(separatedBy: .newlines).first ?? roast.content)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                    }
                                    
                                    if let deletedDate = roast.deletedDate {
                                        Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        roastJokeToDelete = roast
                                        showingDeleteRoastAlert = true
                                    } label: {
                                        Label("Delete Forever", systemImage: "trash.fill")
                                    }

                                    Button {
                                        restoreRoastJoke(roast)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        restoreRoastJoke(roast)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }

                                    Button(role: .destructive) {
                                        roastJokeToDelete = roast
                                        showingDeleteRoastAlert = true
                                    } label: {
                                        Label("Delete Forever", systemImage: "trash.fill")
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.blue)
                                Text("Roasts (\(filteredRoastJokes.count))")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search trash")
        .toolbar {
            if totalTrashedCount > 0 {
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
                    permanentlyDeleteJoke(joke)
                    jokeToDelete = nil
                }
            }
        } message: {
            Text("This joke will be permanently deleted. This cannot be undone.")
        }
        .alert("Delete Roast Forever?", isPresented: $showingDeleteRoastAlert) {
            Button("Cancel", role: .cancel) { roastJokeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let roast = roastJokeToDelete {
                    permanentlyDeleteRoastJoke(roast)
                    roastJokeToDelete = nil
                }
            }
        } message: {
            Text("This roast will be permanently deleted. This cannot be undone.")
        }
        .alert("Empty Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                emptyTrash()
            }
        } message: {
            Text("This permanently deletes all \(totalTrashedCount) item\(totalTrashedCount == 1 ? "" : "s") in trash. This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
        .onAppear {
            logTrashCounts()
        }
    }

    // MARK: - Actions

    private func restoreJoke(_ joke: Joke) {
        joke.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to restore joke: \(error)")
            persistenceError = "Could not restore joke: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func restoreRoastJoke(_ roast: RoastJoke) {
        roast.restoreFromTrash()
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to restore roast: \(error)")
            persistenceError = "Could not restore roast: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func permanentlyDeleteJoke(_ joke: Joke) {
        modelContext.delete(joke)
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to permanently delete joke: \(error)")
            persistenceError = "Could not delete joke: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func permanentlyDeleteRoastJoke(_ roast: RoastJoke) {
        modelContext.delete(roast)
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to permanently delete roast: \(error)")
            persistenceError = "Could not delete roast: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }

    private func emptyTrash() {
        // Delete all jokes
        for joke in trashedJokes {
            modelContext.delete(joke)
        }
        // Delete all roast jokes
        for roast in trashedRoastJokes {
            modelContext.delete(roast)
        }
        do {
            try modelContext.save()
        } catch {
            print(" [TrashView] Failed to empty trash: \(error)")
            persistenceError = "Could not empty trash: \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
    .modelContainer(for: [Joke.self, RoastJoke.self], inMemory: true)
}
