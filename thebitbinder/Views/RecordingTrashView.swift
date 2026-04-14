//
//  RecordingTrashView.swift
//  thebitbinder
//
//  Trash bin for soft-deleted recordings.
//  Restore puts the recording back in the active list.
//  "Delete Forever" removes the audio file from disk then the DB record.
//

import SwiftUI
import SwiftData

struct RecordingTrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Recording> { $0.isDeleted == true },
        sort: \Recording.deletedDate,
        order: .reverse
    ) private var trashedRecordings: [Recording]

    @State private var searchText = ""
    @State private var showingEmptyTrashAlert = false
    @State private var persistenceError: String?
    @State private var showingErrorAlert = false

    private var filtered: [Recording] {
        let t = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return trashedRecordings }
        return trashedRecordings.filter { $0.title.lowercased().contains(t) }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                BitBinderEmptyState(
                    icon: "trash",
                    title: "Recording Trash is Empty",
                    subtitle: "Deleted recordings appear here for 30 days before being permanently removed."
                )
            } else {
                List {
                    ForEach(filtered) { recording in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recording.title)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Text(durationString(from: recording.duration))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let deletedDate = recording.deletedDate {
                                    Text("Deleted \(deletedDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                RecordingsView.permanentlyDelete(recording, context: modelContext)
                            } label: {
                                Label("Delete Forever", systemImage: "trash.fill")
                            }

                            Button {
                                recording.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print(" [RecordingTrashView] Failed to restore recording: \(error)")
                                    persistenceError = "Could not restore recording: \(error.localizedDescription)"
                                    showingErrorAlert = true
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                recording.restoreFromTrash()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print(" [RecordingTrashView] Failed to restore recording: \(error)")
                                    persistenceError = "Could not restore recording: \(error.localizedDescription)"
                                    showingErrorAlert = true
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }

                            Button(role: .destructive) {
                                RecordingsView.permanentlyDelete(recording, context: modelContext)
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
            if !trashedRecordings.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingEmptyTrashAlert = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash.slash")
                    }
                }
            }
        }
        .alert("Empty Recording Trash?", isPresented: $showingEmptyTrashAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty", role: .destructive) {
                for recording in trashedRecordings {
                    RecordingsView.permanentlyDelete(recording, context: modelContext)
                }
            }
        } message: {
            Text("This permanently deletes all \(trashedRecordings.count) recording\(trashedRecordings.count == 1 ? "" : "s") and their audio files. This cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }

    private func durationString(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        RecordingTrashView()
    }
    .modelContainer(for: Recording.self, inMemory: true)
}
