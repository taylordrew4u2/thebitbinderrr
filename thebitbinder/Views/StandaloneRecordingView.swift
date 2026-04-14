//
//  StandaloneRecordingView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/3/26.
//

import SwiftUI
import SwiftData
import AVFoundation

struct StandaloneRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var audioService = AudioRecordingService()
    @State private var recordingName = ""
    @State private var showingSaveAlert = false
    @State private var showingDiscardAlert = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var microphonePermissionGranted: Bool = false
    @State private var microphonePermissionDenied: Bool = false
    @State private var showingPermissionDenied = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Permission denied state
                if microphonePermissionDenied {
                    permissionDeniedView
                } else {
                    recordingContent
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if audioService.isRecording {
                            // Show confirmation before discarding
                            showingDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Save Recording", isPresented: $showingSaveAlert) {
                TextField("Recording name", text: $recordingName)
                Button("Save") {
                    saveRecording()
                }
                Button("Discard", role: .destructive) {
                    discardRecording()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter a name for your recording")
            }
            .alert("Discard Recording?", isPresented: $showingDiscardAlert) {
                Button("Discard", role: .destructive) {
                    audioService.cancelRecording()
                    dismiss()
                }
                Button("Keep Recording", role: .cancel) { }
            } message: {
                Text("Your recording will be lost if you discard it.")
            }
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
        .onAppear {
            checkMicrophonePermission()
            recordingName = "Recording - \(Date().formatted(date: .abbreviated, time: .shortened))"
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Permission Handling
    
    private func checkMicrophonePermission() {
        if #available(iOS 17.0, *) {
            let status = AVAudioApplication.shared.recordPermission
            switch status {
            case .granted:
                microphonePermissionGranted = true
                microphonePermissionDenied = false
            case .denied:
                microphonePermissionGranted = false
                microphonePermissionDenied = true
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        microphonePermissionGranted = granted
                        microphonePermissionDenied = !granted
                    }
                }
            @unknown default:
                microphonePermissionGranted = false
            }
        } else {
            let status = AVAudioSession.sharedInstance().recordPermission
            switch status {
            case .granted:
                microphonePermissionGranted = true
                microphonePermissionDenied = false
            case .denied:
                microphonePermissionGranted = false
                microphonePermissionDenied = true
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        microphonePermissionGranted = granted
                        microphonePermissionDenied = !granted
                    }
                }
            @unknown default:
                microphonePermissionGranted = false
            }
        }
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Microphone Access Required")
                .font(.headline)
            
            Text("BitBinder needs microphone access to record your performances and ideas.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Recording Content
    
    private var recordingContent: some View {
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
                            .foregroundColor(.red)
                        
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
                    .stroke(audioService.isRecording ? Color.red : Color.accentColor, lineWidth: 4)
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
                    .foregroundColor(audioService.isRecording ? .red : .accentColor)
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
                                    .foregroundColor(.red)
                            }
                            Text("Start")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .disabled(!microphonePermissionGranted)
                } else {
                    Button(action: pauseResumeRecording) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 70, height: 70)
                                Image(systemName: audioService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
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
                                    .foregroundColor(.red)
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
                            .foregroundStyle(.blue)
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
    
    // MARK: - Recording Actions
    
    private func startRecording() {
        guard microphonePermissionGranted else {
            showingPermissionDenied = true
            return
        }
        
        // Sanitize filename - remove special characters that could cause issues
        let sanitizedName = sanitizeFileName(recordingName.isEmpty ? "Recording" : recordingName)
        let started = audioService.startRecording(fileName: sanitizedName)
        if started {
            haptic(.light)
            recordingDuration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingDuration += 1
            }
        }
    }
    
    private func pauseResumeRecording() {
        haptic(.light)
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
        haptic(.medium)
        timer?.invalidate()
        let result = audioService.stopRecording()
        recordingDuration = result.duration
        showingSaveAlert = true
    }
    
    private func saveRecording() {
        guard let fileURL = audioService.recordingURL else {
            saveErrorMessage = "Recording file not found. Please try again."
            showingSaveError = true
            return
        }
        
        // Verify file exists before saving to database
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            saveErrorMessage = "Recording file was not created. Please try again."
            showingSaveError = true
            return
        }
        
        // Store just the filename, not the full path (paths change between app launches)
        let fileName = fileURL.lastPathComponent
        
        // Sanitize the display name
        let displayName = recordingName.isEmpty 
            ? "Recording \(Date().formatted(date: .abbreviated, time: .shortened))" 
            : recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let recording = Recording(
            title: displayName,
            fileURL: fileName,
            duration: recordingDuration
        )
        
        modelContext.insert(recording)
        
        // Save context explicitly with error handling
        do {
            try modelContext.save()
            haptic(.success)
            dismiss()
        } catch {
            // Remove the inserted object since save failed
            modelContext.delete(recording)
            saveErrorMessage = "Could not save recording: \(error.localizedDescription)"
            showingSaveError = true
        }
    }
    
    private func discardRecording() {
        audioService.cancelRecording()
        dismiss()
    }
    
    // MARK: - Helpers
    
    /// Sanitizes a filename by removing characters that could cause filesystem issues
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Limit length to prevent filesystem issues
        if sanitized.count > 100 {
            sanitized = String(sanitized.prefix(100))
        }
        
        // Ensure we have a valid name
        if sanitized.isEmpty {
            sanitized = "Recording_\(UUID().uuidString.prefix(8))"
        }
        
        return sanitized
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
