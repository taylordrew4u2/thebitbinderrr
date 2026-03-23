//
//  RecordRoastSetView.swift
//  thebitbinder
//
//  A view for recording a full stand-up set focused on a roast target,
//  then splitting the recording into individual roast jokes.
//

import SwiftUI
import AVFoundation

struct RecordRoastSetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let target: RoastTarget
    
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var showDiscardAlert = false
    
    private let accentColor = AppTheme.Colors.roastAccent
    
    var formattedTime: String {
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? AppTheme.Colors.recordingsAccent.opacity(0.15) : accentColor.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                        
                        Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                            .font(.system(size: 40))
                            .foregroundColor(isRecording ? .red : accentColor)
                            .symbolEffect(.variableColor, isActive: isRecording)
                    }
                    
                    Text(isRecording ? "Recording..." : "Record Set")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Recording for \(target.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    // Time display
                    Text(formattedTime)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(isRecording ? .red : accentColor)
                        .padding()
                        .background(AppTheme.Colors.surfaceElevated)
                        .cornerRadius(12)
                }
                .padding(.top, 20)
                
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(accentColor)
                        Text("Record your full set, then review and split into individual roasts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.recordingsAccent)
                        .padding(.horizontal, 20)
                }
                
                // Controls
                VStack(spacing: 16) {
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                                .font(.system(size: 20))
                            Text(isRecording ? "Stop Recording" : "Start Recording")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isRecording ? AppTheme.Colors.recordingsAccent : accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    if recordingURL != nil && !isRecording {
                        Button {
                            // For now, we'll just save it as a single roast
                            // In the future, this could transcribe and split
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                Text("Done")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.Colors.success)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if isRecording || recordingURL != nil {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Discard Recording?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    stopRecording()
                    // Clean up temp file
                    if let url = recordingURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    dismiss()
                }
                Button("Keep Recording", role: .cancel) { }
            } message: {
                Text("You have an active or unsaved recording. Are you sure you want to discard it?")
            }
            .onDisappear {
                if isRecording {
                    stopRecording()
                }
            }
        }
    }
    
    private func startRecording() {
        Task {
            // Request microphone permission
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                        continuation.resume(returning: allowed)
                    }
                }
            }
            
            guard granted else {
                await MainActor.run {
                    self.errorMessage = "Microphone permission required"
                }
                return
            }
            
            await MainActor.run {
                guard setupAudioSession() else { return }
                
                // Slugify target id to ensure a valid filename component
                let safeID = sanitizedFilenameComponent(from: target.id.uuidString)
                let filename = FileManager.default.temporaryDirectory
                    .appendingPathComponent("roast_set_\(safeID).m4a")
                
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                
                do {
                    audioRecorder = try AVAudioRecorder(url: filename, settings: settings)
                    audioRecorder?.record()
                    
                    recordingURL = filename
                    recordingTime = 0
                    isRecording = true
                    errorMessage = nil
                    
                    // Start timer — capture self weakly to avoid retain cycles
                    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak audioRecorder] _ in
                        guard audioRecorder?.isRecording == true else { return }
                        recordingTime += 0.1
                    }
                } catch {
                    errorMessage = "Failed to start recording: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    /// Returns `true` when the audio session is ready; sets `errorMessage` and
    /// returns `false` on failure so the caller can bail out.
    @discardableResult
    private func setupAudioSession() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Strips any characters that are unsafe for use in a filename.
    private func sanitizedFilenameComponent(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
    }
}

#Preview {
    RecordRoastSetView(target: RoastTarget(name: "Dave Chappelle", notes: "Comedy legend"))
}
