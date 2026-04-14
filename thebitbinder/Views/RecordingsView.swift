//
//  RecordingsView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct RecordingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Recording> { !$0.isDeleted }, sort: \Recording.dateCreated, order: .reverse) private var recordings: [Recording]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var searchText = ""
    @State private var showingQuickRecord = false
    @State private var showingTrash = false
    @State private var persistenceError: String?
    @State private var showingPersistenceError = false
    
    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        } else {
            return recordings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        Group {
            if filteredRecordings.isEmpty {
                BitBinderEmptyState(
                    icon: "mic.circle.fill",
                    title: roastMode ? "No Recordings" : "No Recordings Yet",
                    subtitle: "Record your sets to review and improve your delivery",
                    actionTitle: "Start Recording",
                    action: { showingQuickRecord = true },
                    roastMode: roastMode
                )
            } else {
                List {
                    ForEach(filteredRecordings) { recording in
                        NavigationLink(destination: RecordingDetailView(recording: recording)) {
                            RecordingRowView(recording: recording)
                        }
                    }
                    .onDelete(perform: deleteRecordings)
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, prompt: "Search recordings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingQuickRecord = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Section {
                        Button { showingTrash = true } label: {
                            Label("Trash", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingTrash) {
            RecordingTrashView()
        }
        .sheet(isPresented: $showingQuickRecord) {
            StandaloneRecordingView()
        }
        .alert("Error", isPresented: $showingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown error occurred")
        }
    }
    
    /// Soft-deletes the recording DB record. Audio file is preserved until permanent purge.
    /// This prevents the scenario where the audio file is deleted but the DB save fails.
    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            filteredRecordings[index].moveToTrash()
        }
        do {
            try modelContext.save()
        } catch {
            print(" [RecordingsView] Failed to save after soft-delete: \(error)")
            persistenceError = "Could not move recording to trash: \(error.localizedDescription)"
            showingPersistenceError = true
        }
    }

    /// Permanently deletes a recording: removes the audio file, then removes the DB record.
    /// Only call this when the user explicitly confirms permanent deletion (e.g. from a trash view).
    static func permanentlyDelete(_ recording: Recording, context: ModelContext) {
        // Resolve audio file URL (handles stale absolute paths)
        let fileURL = recording.resolvedURL

        // Delete the audio file first, then the DB record
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                // Log but don't abort — the DB record should still be removed
                print(" [RecordingsView] Failed to delete audio file '\(fileURL.lastPathComponent)': \(error)")
            }
        }

        context.delete(recording)
        do {
            try context.save()
        } catch {
            print(" [RecordingsView] Failed to save after permanent recording deletion: \(error)")
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording
    @AppStorage("roastModeEnabled") private var roastMode = false

    var body: some View {
        HStack(spacing: 12) {
            // Play icon
            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Text(durationString(from: recording.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if recording.transcription != nil {
                        Text("Transcribed")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Text(recording.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption)
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 6)
    }
    
    private func durationString(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
