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
    @AppStorage("showFullContent") private var showFullContent = true
    
    @Bindable var setList: SetList
    @State private var showingAddJokes = false
    @State private var isEditing = false
    
    // Finalize & Performance
    @State private var showingFinalizeSheet = false
    @State private var showingLivePerformance = false
    @State private var showingUnfinalizeAlert = false
    
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
            // Finalized banner (when set is ready for performance)
            if setList.isFinalized {
                finalizedBanner
            } else if setList.totalItemCount > 0 {
                // Quick perform banner when NOT finalized but has jokes
                quickPerformBanner
            }
            
             // Inline recording header
             VStack(spacing: 12) {
                 HStack {
                     if audioService.isRecording {
                         Circle().fill(Color.red).frame(width: 12, height: 12)
                             .opacity(0.8)
                             .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioService.isRecording)
                         Text("Recording").font(.headline).foregroundColor(.red)
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
                                 .foregroundColor(.red)
                         }
                         .accessibilityLabel("Start Recording")
                     } else {
                         Button(action: pauseResumeRecording) {
                             Image(systemName: audioService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                 .font(.system(size: 40))
                                 .foregroundColor(.accentColor)
                         }
                         .accessibilityLabel(audioService.isPaused ? "Resume" : "Pause")
                         
                         Button(action: stopRecording) {
                             Image(systemName: "stop.circle.fill")
                                 .font(.system(size: 40))
                                 .foregroundColor(.red)
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
                    ContentUnavailableView {
                        Label("No Roast Jokes", systemImage: "flame")
                    } description: {
                        Text("Add roast jokes to build your set.")
                    } actions: {
                        Button("Add Roast Jokes") { showingAddJokes = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                    }
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
                    ContentUnavailableView {
                        Label("No Jokes Yet", systemImage: "text.quote")
                    } description: {
                        Text("Add jokes to build your set list.")
                    } actions: {
                        Button("Add Jokes") { showingAddJokes = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(setListJokes) { joke in
                            JokeRowView(joke: joke, showFullContent: showFullContent)
                        }
                        .onMove(perform: moveJokes)
                        .onDelete(perform: deleteJokes)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Leading: GO LIVE button - always visible when set has jokes
            ToolbarItem(placement: .navigationBarLeading) {
                if setList.totalItemCount > 0 {
                    Button {
                        showingLivePerformance = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("GO LIVE")
                                .fontWeight(.bold)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(setList.isFinalized ? Color.blue : Color.blue)
                        .clipShape(Capsule())
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Finalize / Unfinalize
                    if setList.isFinalized {
                        Button {
                            showingLivePerformance = true
                        } label: {
                            Label("Start Performance", systemImage: "play.fill")
                        }
                        
                        Button(role: .destructive) {
                            showingUnfinalizeAlert = true
                        } label: {
                            Label("Unfinalize (Allow Edits)", systemImage: "lock.open")
                        }
                    } else {
                        Button {
                            showingFinalizeSheet = true
                        } label: {
                            Label("Finalize for Performance", systemImage: "checkmark.seal")
                        }
                        .disabled(setList.totalItemCount == 0)
                    }
                    
                    Divider()
                    
                    Button(action: { showingAddJokes = true }) {
                        Label(roastMode ? "Add Roast Jokes" : "Add Jokes", systemImage: "plus")
                    }
                    .disabled(setList.isFinalized)
                    
                    Button(action: { showFullContent.toggle() }) {
                        Label(showFullContent ? "Show Titles Only" : "Show Full Content", systemImage: showFullContent ? "list.bullet" : "text.justify.leading")
                    }
                    
                    Button(action: { isEditing.toggle() }) {
                        Label(isEditing ? "Done" : "Edit Order", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(setList.isFinalized)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .environment(\.editMode, .constant(isEditing && !setList.isFinalized ? .active : .inactive))
        .sheet(isPresented: $showingAddJokes) {
            if roastMode {
                AddRoastJokesToSetListView(setList: setList, currentRoastJokeIDs: setList.roastJokeIDs)
            } else {
                AddJokesToSetListView(setList: setList, currentJokeIDs: setList.jokeIDs)
            }
        }
        .sheet(isPresented: $showingFinalizeSheet) {
            FinalizeSetSheet(setList: setList)
        }
        .fullScreenCover(isPresented: $showingLivePerformance) {
            LivePerformanceView(setList: setList)
        }
        .alert("Unfinalize Set?", isPresented: $showingUnfinalizeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unfinalize") {
                unfinalizeSet()
            }
        } message: {
            Text("This will allow editing the set again. You can re-finalize anytime before your performance.")
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
            fileURL: fileURL.lastPathComponent,
            duration: recordingDuration
        )
        modelContext.insert(recording)
        
        // Try to save the context
        do {
            try modelContext.save()
            #if DEBUG
            print("Recording saved successfully: \(recording.title)")
            #endif
        } catch {
            #if DEBUG
            print(" Failed to save recording: \(error)")
            #endif
        }
        
        // Reset state
        lastRecordingURL = nil
        recordingDuration = 0
    }
    
    private func moveJokes(from source: IndexSet, to destination: Int) {
        setList.jokeIDs.move(fromOffsets: source, toOffset: destination)
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [SetListDetailView] Failed to save joke move: \(error)")
            #endif
        }
    }
    
    private func deleteJokes(at offsets: IndexSet) {
        for index in offsets {
            if index < setList.jokeIDs.count {
                setList.jokeIDs.remove(at: index)
            }
        }
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [SetListDetailView] Failed to save joke deletion: \(error)")
            #endif
        }
    }
    
    // MARK: - Roast Joke Helpers
    
    @ViewBuilder
    private func roastJokeRow(_ joke: RoastJoke) -> some View {
            HStack(alignment: .top, spacing: 12) {
                 Image(systemName: "flame.fill")
                     .font(.system(size: 14))
                     .foregroundColor(.blue)
                     .padding(.top, 3)
                 
                 VStack(alignment: .leading, spacing: 4) {
                     if showFullContent {
                         Text(joke.content)
                             .font(.system(size: 15))
                             .foregroundColor(.primary)
                     } else {
                         Text(joke.content.components(separatedBy: .newlines).first ?? joke.content)
                             .font(.system(size: 15, weight: .medium))
                             .foregroundColor(.primary)
                             .lineLimit(1)
                     }
                     
                     if let targetName = joke.target?.name {
                         Text("for \(targetName)")
                             .font(.system(size: 12, weight: .medium))
                             .foregroundColor(.blue.opacity(0.8))
                     }
                 }
             }
        .padding(.vertical, 4)
    }
    
    private func moveRoastJokes(from source: IndexSet, to destination: Int) {
        setList.roastJokeIDs.move(fromOffsets: source, toOffset: destination)
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [SetListDetailView] Failed to save roast joke move: \(error)")
            #endif
        }
    }
    
    private func deleteRoastJokes(at offsets: IndexSet) {
        for index in offsets {
            if index < setList.roastJokeIDs.count {
                setList.roastJokeIDs.remove(at: index)
            }
        }
        setList.dateModified = Date()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [SetListDetailView] Failed to save roast joke deletion: \(error)")
            #endif
        }
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Finalized Banner
    
    private var finalizedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to Perform")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    if setList.estimatedMinutes > 0 {
                        Text("\(setList.estimatedMinutes) min")
                    }
                    if !setList.venueName.isEmpty {
                        Text("•")
                        Text(setList.venueName)
                    }
                    if let perfDate = setList.performanceDate {
                        Text("•")
                        Text(perfDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            Button {
                showingLivePerformance = true
            } label: {
                Text("GO LIVE")
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color.blue)
    }
    
    // MARK: - Quick Perform Banner (for unfinalized sets)
    
    private var quickPerformBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(setList.totalItemCount) joke\(setList.totalItemCount == 1 ? "" : "s") ready")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Tap GO LIVE to perform • Finalize for full features")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            VStack(spacing: 6) {
                Button {
                    showingLivePerformance = true
                } label: {
                    Text("GO LIVE")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                
                Button {
                    showingFinalizeSheet = true
                } label: {
                    Text("Finalize")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding()
        .background(Color.blue)
    }
    
    private func unfinalizeSet() {
        setList.unfinalize()
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("⚠️ [SetListDetailView] Failed to unfinalize: \(error)")
            #endif
        }
    }
}