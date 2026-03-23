//
//  RecordingView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var jokes: [Joke]
    
    var setList: SetList
    
    @StateObject private var recordingService = AudioRecordingService()
    @State private var recordingName = ""
    @State private var showingSaveAlert = false
    @State private var currentJokeIndex = 0
    @State private var showAllJokes = false
    
    var setListJokes: [Joke] {
        setList.jokeIDs.compactMap { jokeID in
            jokes.first { $0.id == jokeID }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Recording status header
                VStack(spacing: 12) {
                    HStack {
                        HStack(spacing: 8) {
                            if recordingService.isRecording {
                                Circle()
                                    .fill(AppTheme.Colors.recordingsAccent)
                                    .frame(width: 12, height: 12)
                                    .opacity(0.8)
                                    .scaleEffect(1.1)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: recordingService.isRecording)
                            }
                            Text(recordingService.isRecording ? "RECORDING" : "Ready to Record")
                                .font(.headline)
                                .foregroundColor(recordingService.isRecording ? .red : .secondary)
                        }
                        
                        Spacer()
                        
                        if recordingService.isRecording {
                            Text(timeString(from: recordingService.recordingTime))
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.Colors.recordingsAccent)
                        }
                    }
                    
                    Text(setList.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                
                // Jokes display
                if setListJokes.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No jokes in this set list")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if showAllJokes {
                        // Show all jokes in a scrollable list
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(setListJokes.enumerated()), id: \.element.id) { index, joke in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("\(index + 1).")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 30, alignment: .leading)
                                            Text(joke.title)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            
                                            if index == currentJokeIndex {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                            }
                                        }
                                        
                                        Text(joke.content)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .padding(.leading, 38)
                                    }
                                    .padding()
                                    .background(index == currentJokeIndex ? AppTheme.Colors.primaryAction.opacity(0.1) : Color.clear)
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        currentJokeIndex = index
                                        showAllJokes = false
                                    }
                                    
                                    if index < setListJokes.count - 1 {
                                        Divider()
                                            .padding(.leading, 38)
                                    }
                                }
                            }
                            .padding()
                        }
                    } else {
                        // Show current joke with navigation
                        VStack(spacing: 20) {
                            // Joke counter
                            Text("\(currentJokeIndex + 1) of \(setListJokes.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top)
                            
                            // Current joke display
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(setListJokes[currentJokeIndex].title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    Text(setListJokes[currentJokeIndex].content)
                                        .font(.body)
                                        .lineSpacing(6)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // Joke navigation
                            HStack(spacing: 20) {
                                Button(action: previousJoke) {
                                    Image(systemName: "chevron.left.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(currentJokeIndex > 0 ? .blue : .gray)
                                }
                                .disabled(currentJokeIndex == 0)
                                
                                Spacer()
                                
                                Button(action: { showAllJokes = true }) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "list.bullet")
                                            .font(.system(size: 20))
                                        Text("View All")
                                            .font(.caption)
                                    }
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                }
                                
                                Spacer()
                                
                                Button(action: nextJoke) {
                                    Image(systemName: "chevron.right.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(currentJokeIndex < setListJokes.count - 1 ? .blue : .gray)
                                }
                                .disabled(currentJokeIndex >= setListJokes.count - 1)
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                // Recording controls at bottom
                VStack(spacing: 12) {
                    Divider()
                    
                    if !recordingService.isRecording {
                        Button(action: startRecording) {
                            HStack {
                                Image(systemName: "record.circle.fill")
                                Text("Start Recording")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.Colors.recordingsAccent)
                            .cornerRadius(12)
                        }
                        .disabled(setListJokes.isEmpty)
                    } else {
                        Button(action: { showingSaveAlert = true }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop & Save Recording")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.Colors.recordingsAccent)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(recordingService.isRecording ? "Cancel" : "Close") {
                        if recordingService.isRecording {
                            recordingService.cancelRecording()
                        }
                        dismiss()
                    }
                    .foregroundColor(recordingService.isRecording ? .red : .blue)
                }
                
                if showAllJokes {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Single View") {
                            showAllJokes = false
                        }
                    }
                }
            }
            .alert("Save Recording", isPresented: $showingSaveAlert) {
                TextField("Recording name", text: $recordingName)
                Button("Save") {
                    saveRecording()
                }
                Button("Cancel", role: .cancel) {
                    recordingService.cancelRecording()
                }
            } message: {
                Text("Enter a name for this recording")
            }
        }
    }
    
    private func previousJoke() {
        if currentJokeIndex > 0 {
            currentJokeIndex -= 1
        }
    }
    
    private func nextJoke() {
        if currentJokeIndex < setListJokes.count - 1 {
            currentJokeIndex += 1
        }
    }
    
    private func startRecording() {
        let fileName = "recording_\(Date().timeIntervalSince1970)"
        _ = recordingService.startRecording(fileName: fileName)
    }
    
    private func saveRecording() {
        let result = recordingService.stopRecording()
        
        if let url = result.url {
            let name = recordingName.isEmpty ? "Recording - \(setList.name)" : recordingName
            // Save only the filename, not the full path (sandbox paths change between installs)
            let recording = Recording(
                title: name,
                fileURL: url.lastPathComponent,
                duration: result.duration
            )
            modelContext.insert(recording)
            dismiss()
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
