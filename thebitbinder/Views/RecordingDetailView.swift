//
//  RecordingDetailView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import SwiftUI
import AVFoundation
import SwiftData
import Combine

struct RecordingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var recording: Recording
    @StateObject private var audioPlayer = AudioPlayerService()
    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var showingTranscriptionError = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Player controls
                VStack(spacing: 20) {
                    // Show error if loading failed
                    if let error = audioPlayer.loadError {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.Colors.error.opacity(0.1))
                                    .frame(width: 100, height: 100)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(AppTheme.Colors.error)
                            }
                            
                            Text("Unable to Play")
                                .font(.headline)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                audioPlayer.loadAudio(from: recording.fileURL)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else {
                        ZStack {
                            Circle()
                                .stroke(AppTheme.Colors.primaryAction, lineWidth: 8)
                                .frame(width: 200, height: 200)
                            
                            if audioPlayer.isPlaying {
                                Circle()
                                    .fill(AppTheme.Colors.primaryAction.opacity(0.3))
                                    .frame(width: 180, height: 180)
                            }
                            
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(AppTheme.Colors.primaryAction)
                        }
                        
                        // Progress bar
                        VStack(spacing: 8) {
                            Slider(value: $audioPlayer.currentTime, in: 0...max(audioPlayer.duration, 1), onEditingChanged: { editing in
                                if !editing {
                                    audioPlayer.seek(to: audioPlayer.currentTime)
                                }
                            })
                            .tint(AppTheme.Colors.primaryAction)
                            
                            HStack {
                                Text(timeString(from: audioPlayer.currentTime))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(timeString(from: audioPlayer.duration))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Playback controls
                        HStack(spacing: 40) {
                            Button(action: { audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15)) }) {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 30))
                            }
                            
                            Button(action: togglePlayback) {
                                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 60))
                            }
                            
                            Button(action: { audioPlayer.seek(to: min(audioPlayer.duration, audioPlayer.currentTime + 15)) }) {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 30))
                            }
                        }
                        .foregroundColor(AppTheme.Colors.primaryAction)
                    }
                }
                .padding()
                
                // Transcription section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Transcription", systemImage: "text.quote")
                            .font(.headline)
                        
                        Spacer()
                        
                        if isTranscribing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if recording.transcription == nil {
                            Button(action: transcribeRecording) {
                                Label("Transcribe", systemImage: "waveform")
                                    .font(.subheadline)
                            }
                        } else {
                            Button(action: transcribeRecording) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.subheadline)
                            }
                        }
                    }
                    
                    if let transcription = recording.transcription {
                        Text(transcription)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.Colors.surfaceElevated)
                            .cornerRadius(AppTheme.Radius.medium)
                    } else if isTranscribing {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Transcribing audio...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(AppTheme.Colors.surfaceElevated)
                        .cornerRadius(AppTheme.Radius.medium)
                    } else {
                        Text("Tap 'Transcribe' to convert this recording to text")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.Colors.surfaceElevated)
                            .cornerRadius(AppTheme.Radius.medium)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // Recording info
                VStack(alignment: .leading, spacing: 16) {
                    InfoRow(label: "Name", value: recording.title)
                    InfoRow(label: "Duration", value: timeString(from: recording.duration))
                    InfoRow(label: "Date", value: recording.dateCreated.formatted(date: .long, time: .shortened))
                }
                .padding()
                .background(AppTheme.Colors.surfaceElevated)
                .cornerRadius(AppTheme.Radius.medium)
                .padding(.horizontal)
                
                // Share button
                Button(action: shareRecording) {
                    Label("Share Recording", systemImage: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                                .fill(AppTheme.Colors.primaryAction)
                        )
                }
                .buttonStyle(TouchReactiveStyle(pressedScale: 0.97, hapticStyle: .light))
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Small delay to ensure audio session is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                audioPlayer.loadAudio(from: recording.fileURL)
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .alert("Transcription Error", isPresented: $showingTranscriptionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(transcriptionError ?? "An unknown error occurred")
        }
    }
    
    private func togglePlayback() {
        // Don't try to play if there's a load error
        guard audioPlayer.loadError == nil else {
            audioPlayer.loadAudio(from: recording.fileURL)
            return
        }
        
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else {
            audioPlayer.play()
        }
    }
    
    private func transcribeRecording() {
        isTranscribing = true
        transcriptionError = nil
        
        Task {
            do {
                // Construct the proper file URL from Documents directory
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = documentsPath.appendingPathComponent(recording.fileURL)
                
                let result = try await AudioTranscriptionService.shared.transcribe(audioURL: url)
                
                await MainActor.run {
                    recording.transcription = result.transcription
                    try? modelContext.save()
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    transcriptionError = error.localizedDescription
                    showingTranscriptionError = true
                    isTranscribing = false
                }
            }
        }
    }
    
    private func shareRecording() {
        // Determine the actual file URL (handle both relative and absolute paths)
        var url: URL
        if recording.fileURL.hasPrefix("/") {
            url = URL(fileURLWithPath: recording.fileURL)
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = documentsPath.appendingPathComponent(recording.fileURL)
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Cannot share - file not found: \(url.path)")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var loadError: String?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
        setupMemoryWarningObserver()
    }
    
    deinit {
        cleanup()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAudioSession() {
        // Don't reconfigure - use the app-wide session from AppDelegate
        // AppDelegate already configured .playAndRecord which works for both
        do {
            let session = AVAudioSession.sharedInstance()
            // Just ensure it's active, don't change category
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("✅ Audio session activated for playback")
        } catch {
            print("❌ Failed to activate audio session: \(error)")
            loadError = "Failed to configure audio: \(error.localizedDescription)"
        }
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        // Pause playback on memory warning
        if isPlaying {
            pause()
            print("⚠️ Memory warning - pausing playback")
        }
    }
    
    func loadAudio(from path: String) {
        // Clean up previous audio first
        cleanup()
        loadError = nil
        
        print("🎵 Loading audio from path: \(path)")
        
        // Determine the actual file URL
        var url: URL
        
        // Check if it's a full path or just a filename
        if path.hasPrefix("/") {
            // It's an absolute path - check if file exists there
            url = URL(fileURLWithPath: path)
            print("📂 Trying absolute path: \(url.path)")
            if !FileManager.default.fileExists(atPath: path) {
                // Try extracting just the filename and look in documents
                let filename = URL(fileURLWithPath: path).lastPathComponent
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                url = documentsPath.appendingPathComponent(filename)
                print("📁 File not at original path, trying documents: \(url.path)")
            }
        } else {
            // It's just a filename - look in documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            url = documentsPath.appendingPathComponent(path)
            print("📁 Loading from documents: \(url.path)")
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            let errorMsg = "Audio file not found: \(url.lastPathComponent)"
            print("❌ \(errorMsg)")
            print("📂 Documents directory: \(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path)")
            
            // List files in documents directory for debugging
            if let files = try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path) {
                print("📂 Files in documents: \(files.filter { $0.hasSuffix(".m4a") })")
            }
            
            loadError = errorMsg
            return
        }
        
        print("✅ File exists at: \(url.path)")
        
        // Audio session already configured app-wide in AppDelegate
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            print("✅ Audio loaded successfully: duration = \(duration)s")
        } catch {
            let errorMsg = "Error loading audio: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            loadError = errorMsg
        }
    }
    
    func play() {
        guard let player = audioPlayer else {
            print("⚠️ Cannot play - audio player is nil")
            loadError = "Audio not loaded"
            return
        }
        player.play()
        isPlaying = true
        startTimer()
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
    }
    
    private func startTimer() {
        stopTimer() // Ensure no duplicate timers
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                
                if !player.isPlaying && self.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func cleanup() {
        stopTimer()
        if let player = audioPlayer {
            if player.isPlaying {
                player.stop()
            }
        }
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
    }
    
    // AVAudioPlayerDelegate methods
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        stopTimer()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            print("Audio player decode error: \(error.localizedDescription)")
        }
        isPlaying = false
        stopTimer()
    }
}
