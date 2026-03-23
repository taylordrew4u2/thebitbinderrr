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
    @Query(sort: \Recording.dateCreated, order: .reverse) private var recordings: [Recording]
    @AppStorage("roastModeEnabled") private var roastMode = false

    @State private var searchText = ""
    @State private var showingQuickRecord = false
    @State private var recordingToDelete: Recording?
    
    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        } else {
            return recordings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredRecordings.isEmpty {
                    BitBinderEmptyState(
                        icon: "mic.circle.fill",
                        title: roastMode ? "No Burn Recordings" : "No Recordings Yet",
                        subtitle: "Record your sets to review and improve your delivery",
                        actionTitle: "Start Recording",
                        action: { showingQuickRecord = true },
                        roastMode: roastMode,
                        iconGradient: LinearGradient(
                            colors: [AppTheme.Colors.recordingsAccent, AppTheme.Colors.recordingsAccent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    List {
                        ForEach(filteredRecordings) { recording in
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                RecordingRowView(recording: recording)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    recordingToDelete = recording
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(roastMode ? "🔥 Burn Recordings" : "Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: roastMode ? "Search recordings" : "Search recordings")
            .bitBinderToolbar(roastMode: roastMode)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQuickRecord = true
                    } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.title3)
                            .foregroundStyle(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.recordingsAccent)
                    }
                }
            }
            .sheet(isPresented: $showingQuickRecord) {
                StandaloneRecordingView()
            }
            .alert("Delete Recording?", isPresented: Binding(
                get: { recordingToDelete != nil },
                set: { if !$0 { recordingToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { recordingToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let recording = recordingToDelete {
                        deleteRecording(recording)
                        recordingToDelete = nil
                    }
                }
            } message: {
                if let recording = recordingToDelete {
                    Text(""\(recording.title)" will be permanently deleted along with its audio file. This cannot be undone.")
                }
            }
        }
    }
    
    private func deleteRecording(_ recording: Recording) {
        var fileURL: URL
        if recording.fileURL.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: recording.fileURL)
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            fileURL = documentsPath.appendingPathComponent(recording.fileURL)
        }
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("⚠️ [RecordingsView] Failed to delete audio file '\(fileURL.lastPathComponent)': \(error)")
            }
        }
        
        modelContext.delete(recording)
        do {
            try modelContext.save()
        } catch {
            print("❌ [RecordingsView] Failed to save after recording deletion: \(error)")
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording
    @AppStorage("roastModeEnabled") private var roastMode = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Play button icon
            ZStack {
                Circle()
                    .fill(
                        roastMode
                            ? AppTheme.Colors.roastAccent.opacity(0.15)
                            : AppTheme.Colors.recordingsAccent.opacity(0.12)
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.recordingsAccent)
                    .offset(x: 2) // Optical centering
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    // Duration
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                        Text(durationString(from: recording.duration))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent.opacity(0.8) : AppTheme.Colors.recordingsAccent.opacity(0.85))
                    
                    // Processing indicator
                    if !recording.isProcessed && recording.transcription == nil {
                        HStack(spacing: 3) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Processing")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    } else if recording.transcription != nil {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 9))
                            Text("Transcript")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppTheme.Colors.success.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Date
                    Text(recording.dateCreated.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 11))
                        .foregroundColor(roastMode ? Color.white.opacity(0.4) : AppTheme.Colors.textTertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }
    
    private func durationString(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
