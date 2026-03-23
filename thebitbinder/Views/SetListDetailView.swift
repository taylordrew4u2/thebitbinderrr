
//  SetListDetailView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct SetListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var jokes: [Joke]
    @Query private var roastJokes: [RoastJoke]
    @AppStorage("roastModeEnabled") private var roastMode = false
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    
    @Bindable var setList: SetList
    @State private var showingAddJokes = false
    @State private var isEditing = false
    
    // Recording inline
    @StateObject private var audioService = AudioRecordingService()
    @State private var recordingName = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var lastRecordingURL: URL?
    @State private var timer: Timer?
    @State private var showingSaveAlert = false
    
    var setListJokes: [Joke] {
        setList.jokeIDs.compactMap { jokeID in
            jokes.first { $0.id == jokeID }
        }
    }
    
    var setListRoastJokes: [RoastJoke] {
        setList.roastJokeIDs.compactMap { roastID in
            roastJokes.first { $0.id == roastID }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Inline recording header
            VStack(spacing: 12) {
                HStack {
                    if audioService.isRecording {
                        Circle().fill(AppTheme.Colors.recordingsAccent).frame(width: 12, height: 12)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioService.isRecording)
                        Text("Recording").font(.headline).foregroundColor(AppTheme.Colors.recordingsAccent)
                        Spacer()
                        Text(timeString(from: recordingDuration))
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.primary)
                    } else {
                        Text("Ready to record").font(.headline)
                        Spacer()
                    }
                }
                
                HStack(spacing: 24) {
                    if !audioService.isRecording {
                        Button(action: startRecording) {
                            Label("Start Recording", systemImage: "record.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 44))
                                .foregroundColor(AppTheme.Colors.recordingsAccent)
                        }
                        .accessibilityLabel("Start Recording")
                    } else {
                        Button(action: pauseResumeRecording) {
                            Image(systemName: audioService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.Colors.primaryAction)
                        }
                        .accessibilityLabel(audioService.isPaused ? "Resume" : "Pause")
                        
                        Button(action: stopRecording) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.Colors.recordingsAccent)
                        }
                        .accessibilityLabel("Stop Recording")
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            if roastMode {
                // Roast mode: show roast jokes
                if setListRoastJokes.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "flame")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No roast jokes in this set")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Button(action: { showingAddJokes = true }) {
                            Label("Add Roast Jokes", systemImage: "plus")
                                .padding()
                                .background(AppTheme.Colors.roastAccent)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(setListRoastJokes) { joke in
                            roastJokeRow(joke)
                        }
                        .onMove(perform: moveRoastJokes)
                        .onDelete(perform: deleteRoastJokes)
                    }
                    .listStyle(.plain)
                }
            } else {
                // Regular mode: show regular jokes
                if setListJokes.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No jokes in this set list")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Button(action: { showingAddJokes = true }) {
                            Label("Add Jokes", systemImage: "plus")
                                .padding()
                                .background(AppTheme.Colors.primaryAction)
                                .foregroundColor(.white)
                                .cornerRadius(AppTheme.Radius.medium)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(setListJokes) { joke in
                            JokeRowView(joke: joke)
                        }
                        .onMove(perform: moveJokes)
                        .onDelete(perform: deleteJokes)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle(setList.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingAddJokes = true }) {
                        Label(roastMode ? "Add Roast Jokes" : "Add Jokes", systemImage: "plus")
                    }
                    
                    Button(action: { expandAllJokes.toggle() }) {
                        Label(expandAllJokes ? "Collapse Content" : "Expand Content", systemImage: expandAllJokes ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    }
                    
                    Button(action: { isEditing.toggle() }) {
                        Label(isEditing ? "Done" : "Edit Order", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .sheet(isPresented: $showingAddJokes) {
            if roastMode {
                AddRoastJokesToSetListView(setList: setList, currentRoastJokeIDs: setList.roastJokeIDs)
            } else {
                AddJokesToSetListView(setList: setList, currentJokeIDs: setList.jokeIDs)
            }
        }
        .alert("Save Recording", isPresented: $showingSaveAlert) {
            TextField("Recording name", text: $recordingName)
            Button("Save") { saveRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for your recording")
        }
        .onAppear {
            recordingName = "\(setList.name) - \(Date().formatted(date: .abbreviated, time: .shortened))"
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startRecording() {
        let name = recordingName.isEmpty ? setList.name : recordingName
        if audioService.startRecording(fileName: name) {
            recordingDuration = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
            }
        }
    }
    
    private func pauseResumeRecording() {
        if audioService.isPaused {
            audioService.resumeRecording()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
            }
        } else {
            audioService.pauseRecording()
            timer?.invalidate()
        }
    }
    
    private func stopRecording() {
        timer?.invalidate()
        let result = audioService.stopRecording()
        lastRecordingURL = result.url
        recordingDuration = result.duration
        showingSaveAlert = true
    }
    
    private func saveRecording() {
        guard let fileURL = lastRecordingURL else {
            #if DEBUG
            print("Error: No recording URL available")
            #endif
            return
        }
        let recording = Recording(
            title: recordingName.isEmpty ? "Recording \(Date())" : recordingName,
            fileURL: fileURL.path,
            duration: recordingDuration
        )
        modelContext.insert(recording)
        
        // Try to save the context
        do {
            try modelContext.save()
            #if DEBUG
            print("✅ Recording saved successfully: \(recording.title)")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save recording: \(error)")
            #endif
        }
        
        // Reset state
        lastRecordingURL = nil
        recordingDuration = 0
    }
    
    private func moveJokes(from source: IndexSet, to destination: Int) {
        setList.jokeIDs.move(fromOffsets: source, toOffset: destination)
        setList.dateModified = Date()
    }
    
    private func deleteJokes(at offsets: IndexSet) {
        for index in offsets {
            if index < setList.jokeIDs.count {
                setList.jokeIDs.remove(at: index)
            }
        }
        setList.dateModified = Date()
    }
    
    // MARK: - Roast Joke Helpers
    
    @ViewBuilder
    private func roastJokeRow(_ joke: RoastJoke) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.Colors.roastAccent)
                .padding(.top, 3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(joke.content)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(expandAllJokes ? nil : 3)
                
                if let targetName = joke.target?.name {
                    Text("for \(targetName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.Colors.roastAccent.opacity(0.8))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func moveRoastJokes(from source: IndexSet, to destination: Int) {
        setList.roastJokeIDs.move(fromOffsets: source, toOffset: destination)
        setList.dateModified = Date()
    }
    
    private func deleteRoastJokes(at offsets: IndexSet) {
        for index in offsets {
            if index < setList.roastJokeIDs.count {
                setList.roastJokeIDs.remove(at: index)
            }
        }
        setList.dateModified = Date()
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes, seconds)
    }
}
