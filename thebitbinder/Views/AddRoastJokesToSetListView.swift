//
//  AddRoastJokesToSetListView.swift
//  thebitbinder
//
//  Shows roast targets as expandable sections so the user can pick
//  individual roast jokes to add to a set list.
//

import SwiftUI
import SwiftData

struct AddRoastJokesToSetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<RoastTarget> { !$0.isDeleted }, sort: \RoastTarget.name) private var roastTargets: [RoastTarget]

    @Bindable var setList: SetList
    var currentRoastJokeIDs: [UUID]

    @AppStorage("showFullContent") private var showFullContent = true
    @State private var selectedIDs: Set<UUID> = []
    @State private var expandedTargets: Set<UUID> = []
    @State private var searchText = ""

    private let accent = Color.blue

    // MARK: - Filtered Data

    /// Targets that have at least one available (not-already-added) joke,
    /// optionally narrowed by the search text.
    private var filteredTargets: [RoastTarget] {
        roastTargets.filter { target in
            let available = availableJokes(for: target)
            return !available.isEmpty
        }
    }

    private func availableJokes(for target: RoastTarget) -> [RoastJoke] {
        // Safety check - return empty if target is invalid
        guard target.isValid else { return [] }
        
        let all = (target.jokes ?? [])
            .filter { !$0.isDeleted && !currentRoastJokeIDs.contains($0.id) }
            .sorted { $0.dateCreated > $1.dateCreated }

        guard !searchText.isEmpty else { return all }
        let lower = searchText.lowercased()
        return all.filter {
            $0.title.lowercased().contains(lower) ||
            $0.content.lowercased().contains(lower)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if filteredTargets.isEmpty {
                    emptyState
                } else {
                    jokeList
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search roast jokes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add (\(selectedIDs.count))") {
                        addSelected()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "flame")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No roast jokes available")
                .font(.title3)
                .foregroundColor(.gray)
            Text("All roast jokes are already in this set, or you haven't written any yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jokeList: some View {
        List {
            ForEach(filteredTargets) { target in
                Section {
                    if expandedTargets.contains(target.id) {
                        let jokes = availableJokes(for: target)

                        // Select-all row for this target
                        let allSelected = jokes.allSatisfy { selectedIDs.contains($0.id) }
                        Button {
                            if allSelected {
                                jokes.forEach { selectedIDs.remove($0.id) }
                            } else {
                                jokes.forEach { selectedIDs.insert($0.id) }
                            }
                        } label: {
                            HStack {
                                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(allSelected ? accent : .secondary)
                                Text(allSelected ? "Deselect All" : "Select All")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(accent)
                            }
                        }

                        ForEach(jokes) { joke in
                            roastJokeRow(joke)
                        }
                    }
                } header: {
                    targetHeader(target)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func targetHeader(_ target: RoastTarget) -> some View {
        // Safe property accessors
        let safeName = target.isValid ? target.name : ""
        let safePhotoData = target.isValid ? target.photoData : nil
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedTargets.contains(target.id) {
                    expandedTargets.remove(target.id)
                } else {
                    expandedTargets.insert(target.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Avatar — async background decode
                AsyncAvatarView(
                    photoData: safePhotoData,
                    size: 32,
                    fallbackInitial: String(safeName.prefix(1).uppercased()),
                    accentColor: accent
                )

                Text(safeName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                let available = availableJokes(for: target).count
                Text("\(available)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.8), in: Capsule())

                Image(systemName: expandedTargets.contains(target.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func roastJokeRow(_ joke: RoastJoke) -> some View {
        Button {
            if selectedIDs.contains(joke.id) {
                selectedIDs.remove(joke.id)
            } else {
                selectedIDs.insert(joke.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if showFullContent {
                        Text(joke.content)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    } else {
                        Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: selectedIDs.contains(joke.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedIDs.contains(joke.id) ? accent : .secondary)
                    .font(.title3)
            }
        }
    }

    // MARK: - Actions

    private func addSelected() {
        setList.roastJokeIDs.append(contentsOf: selectedIDs)
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [AddRoastJokesToSetListView] Failed to save added roast jokes: \(error)")
            #endif
        }
        dismiss()
    }
}