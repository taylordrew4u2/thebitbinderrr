//
//  StandaloneRecordingView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/3/26.
//

import SwiftUI
import SwiftData

struct StandaloneRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var audioService = AudioRecordingService()
    @State private var recordingName = ""
    @State private var showingSaveAlert = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recording Status Bar
                VStack(spacing: 20) {
                    if audioService.isRecording {
                        VStack(spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                    .opacity(0.8)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioService.isRecording)
                                
                                Text("Recording")
                                    .font(.headline)
                                    .foregroundColor(AppTheme.Colors.recordingsAccent)
                                
                                Spacer()
                                
                                Text(timeString(from: recordingDuration))
                                    .font(.system(.title2, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                    
                    // Recording Visualization
                    ZStack {
                        Circle()
                            .stroke(audioService.isRecording ? Color.red : Color.blue, lineWidth: 4)
                            .frame(width: 200, height: 200)
                        
                        if audioService.isRecording {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 180, height: 180)
                                .scaleEffect(audioService.isPaused ? 1.0 : 1.1)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: audioService.isPaused)
                        }
                        
                        Image(systemName: audioService.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 60))
                            .foregroundColor(audioService.isRecording ? .red : .blue)
                    }
                    .padding(.vertical, 40)
                    
                    // Recording Controls
                    HStack(spacing: 40) {
                        if !audioService.isRecording {
                            Button(action: startRecording) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red.opacity(0.1))
                                            .frame(width: 80, height: 80)
                                        Image(systemName: "record.circle.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(AppTheme.Colors.recordingsAccent)
                                    }
                                    Text("Start")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                            }
                        } else {
                            Button(action: pauseResumeRecording) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue.opacity(0.1))
                                            .frame(width: 70, height: 70)
                                        Image(systemName: audioService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(AppTheme.Colors.primaryAction)
                                    }
                                    Text(audioService.isPaused ? "Resume" : "Pause")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            Button(action: stopRecording) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.red.opacity(0.1))
                                            .frame(width: 70, height: 70)
                                        Image(systemName: "stop.circle.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(AppTheme.Colors.recordingsAccent)
                                    }
                                    Text("Stop")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Tips
                    if !audioService.isRecording {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                Text("Record your practice sessions, ideas, or full sets")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding()
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Quick Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if audioService.isRecording {
                            audioService.cancelRecording()
                        }
                        dismiss()
                    }
                }
            }
            .alert("Save Recording", isPresented: $showingSaveAlert) {
                TextField("Recording name", text: $recordingName)
                Button("Save") {
                    saveRecording()
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Enter a name for your recording")
            }
        }
        .onAppear {
            recordingName = "Recording - \(Date().formatted(date: .abbreviated, time: .shortened))"
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startRecording() {
        let name = recordingName.isEmpty ? "Recording" : recordingName
        let started = audioService.startRecording(fileName: name)
        if started {
            recordingDuration = 0
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
        recordingDuration = result.duration
        showingSaveAlert = true
    }
    
    private func saveRecording() {
        guard let fileURL = audioService.recordingURL else {
            #if DEBUG
            print("❌ No recording URL found")
            #endif
            dismiss()
            return
        }
        
        // Verify file exists
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        #if DEBUG
        print("📁 Recording file exists: \(fileExists) at \(fileURL.path)")
        #endif
        
        // Store just the filename, not the full path (paths change between app launches)
        let fileName = fileURL.lastPathComponent
        
        let recording = Recording(
            title: recordingName.isEmpty ? "Recording \(Date())" : recordingName,
            fileURL: fileName,
            duration: recordingDuration
        )
        
        #if DEBUG
        print("✅ Saving standalone recording: \(fileName) with duration: \(recordingDuration)s")
        #endif
        modelContext.insert(recording)
        
        // Save context explicitly
        do {
            try modelContext.save()
            #if DEBUG
            print("✅ Recording saved to database")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to save recording to database: \(error)")
            #endif
        }
        
        dismiss()
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    StandaloneRecordingView()
        .modelContainer(for: Recording.self, inMemory: true)
}
