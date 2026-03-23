//  TalkToTextView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/1/26.
//

import SwiftUI
import Speech
import AVFoundation
import AVFAudio

struct TalkToTextView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    let selectedFolder: JokeFolder?
    
    @State private var transcribedText = ""
    @State private var isRecording = false
    @State private var permissionStatus: PermissionStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var errorMessage: String?
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
    }

    private enum MicPermissionStatus {
        case undetermined
        case granted
        case denied
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? AppTheme.Colors.recordingsAccent.opacity(0.15) : AppTheme.Colors.primaryAction.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isRecording ? AppTheme.Colors.recordingsAccent : AppTheme.Colors.primaryAction)
                            .symbolEffect(.variableColor, isActive: isRecording)
                    }
                    
                    Text(isRecording ? "Listening..." : "Talk-to-Text")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Speak your joke and it will be transcribed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Live transcription area
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transcription")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        if !transcribedText.isEmpty {
                            Button("Clear") {
                                transcribedText = ""
                            }
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.primaryAction)
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                            .fill(AppTheme.Colors.surfaceElevated)
                        
                        if transcribedText.isEmpty && !isRecording {
                            Text("Your transcription will appear here...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(14)
                        }
                        
                        ScrollView {
                            Text(transcribedText)
                                .font(.body)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minHeight: 200)
                }
                .padding(.horizontal, 20)
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.error)
                        .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Controls
                VStack(spacing: 16) {
                    // Main record button
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 20))
                            Text(isRecording ? "Stop" : "Start Recording")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isRecording ? AppTheme.Colors.recordingsAccent : AppTheme.Colors.primaryAction)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(permissionStatus == .denied)
                    
                    // Save button (only show when there's text and not recording)
                    if !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                        Button {
                            saveJoke()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                Text("Save as Joke")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green)
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
                        if isRecording {
                            stopRecording()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkPermissions()
            }
            .alert("Permissions Required", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Microphone and Speech Recognition permissions are required for Talk-to-Text. Please enable them in Settings.")
            }
            .onChange(of: speechRecognizer.transcribedText) { _, newValue in
                transcribedText = newValue
            }
            .onChange(of: speechRecognizer.error) { _, newValue in
                errorMessage = newValue
            }
        }
    }
    
    private func checkPermissions() {
        Task {
            let speechStatus = SFSpeechRecognizer.authorizationStatus()
            let audioStatus = currentMicPermission()
            
            if speechStatus == .authorized && audioStatus == .granted {
                await MainActor.run {
                    permissionStatus = .authorized
                }
            } else if speechStatus == .denied || audioStatus == .denied {
                await MainActor.run {
                    permissionStatus = .denied
                    showingPermissionAlert = true
                }
            } else {
                // Request permissions
                await requestPermissions()
            }
        }
    }

    private func currentMicPermission() -> MicPermissionStatus {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .undetermined
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .undetermined
            }
        }
    }
    
    private func requestPermissions() async {
        // Request speech recognition permission
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
        // Request microphone permission
        let micGranted = await requestMicPermission()
        
        await MainActor.run {
            if speechGranted && micGranted {
                permissionStatus = .authorized
            } else {
                permissionStatus = .denied
                showingPermissionAlert = true
            }
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    private func startRecording() {
        guard permissionStatus == .authorized else {
            showingPermissionAlert = true
            return
        }
        
        // Stop any prior session first
        speechRecognizer.stopTranscribing()
        
        errorMessage = nil
        isRecording = true
        speechRecognizer.startTranscribing()
    }
    
    private func stopRecording() {
        isRecording = false
        speechRecognizer.stopTranscribing()
    }
    
    private func saveJoke() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Create the joke
        let newJoke = Joke(
            content: text,
            title: generateTitle(from: text),
            folder: selectedFolder
        )
        
        modelContext.insert(newJoke)
        try? modelContext.save()
        
        dismiss()
    }
    
    private func generateTitle(from text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        let titleWords = words.prefix(5).joined(separator: " ")
        if words.count > 5 {
            return titleWords + "..."
        }
        return titleWords
    }
}

// MARK: - Speech Recognizer
class SpeechRecognizer: ObservableObject {
    @Published var transcribedText = ""
    @Published var error: String?
    @Published var isTranscribing = false
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    /// Whether the recognizer should keep restarting (true while user wants to record)
    private var shouldBeRunning = false
    /// Accumulated text from previous recognition segments (auto-restart appends here)
    private var accumulatedText = ""
    
    func startTranscribing() {
        // Don't reset text — preserve anything already transcribed
        error = nil
        shouldBeRunning = true
        accumulatedText = transcribedText
        
        startRecognitionSession()
    }
    
    /// Internal: starts or restarts one speech recognition session.
    private func startRecognitionSession() {
        // Clean up any previous session without clearing state
        tearDownAudioPipeline()
        
        guard shouldBeRunning else { return }
        
        // Check if speech recognizer is available
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            DispatchQueue.main.async {
                self.error = "Speech recognition is not available"
                self.isTranscribing = false
            }
            return
        }
        
        // Configure audio session — use playAndRecord to avoid conflicts with
        // AudioRecordingService which also uses playAndRecord.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to configure audio session: \(error.localizedDescription)"
                self.isTranscribing = false
            }
            return
        }
        
        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        
        // Set up audio engine
        let engine = AVAudioEngine()
        audioEngine = engine
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Guard against invalid format (sample rate of 0 on some devices)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            DispatchQueue.main.async {
                self.error = "Audio input format is invalid. Please check your microphone."
                self.isTranscribing = false
            }
            return
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                isFinal = result.isFinal
                let newText = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    // Combine accumulated text from prior segments with current partial result
                    if self.accumulatedText.isEmpty {
                        self.transcribedText = newText
                    } else {
                        self.transcribedText = self.accumulatedText + " " + newText
                    }
                }
            }
            
            if let error = error {
                let nsError = error as NSError
                // Code 216 = user cancelled, code 1110 = no speech detected (timeout)
                let isTimeout = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
                let isCancelled = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216
                
                if isCancelled {
                    // User explicitly stopped — do nothing
                    return
                }
                
                if isTimeout || isFinal {
                    // Speech recognition timed out (~60s) or finished —
                    // save what we have and restart automatically
                    DispatchQueue.main.async {
                        self.accumulatedText = self.transcribedText
                        if self.shouldBeRunning {
                            // Brief delay then restart to keep listening
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.startRecognitionSession()
                            }
                        }
                    }
                    return
                }
                
                // Real error — show it
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isTranscribing = false
                }
                return
            }
            
            // If result is final (e.g. recognizer decided speech ended), auto-restart
            if isFinal {
                DispatchQueue.main.async {
                    self.accumulatedText = self.transcribedText
                    if self.shouldBeRunning {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.startRecognitionSession()
                        }
                    }
                }
            }
        }
        
        // Start audio engine
        do {
            engine.prepare()
            try engine.start()
            DispatchQueue.main.async {
                self.isTranscribing = true
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to start audio engine: \(error.localizedDescription)"
                self.isTranscribing = false
            }
        }
    }
    
    func stopTranscribing() {
        shouldBeRunning = false
        tearDownAudioPipeline()
        accumulatedText = ""
        DispatchQueue.main.async {
            self.isTranscribing = false
        }
    }
    
    /// Tears down audio engine and recognition without resetting user-facing state.
    private func tearDownAudioPipeline() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
    }
    
    deinit {
        shouldBeRunning = false
        tearDownAudioPipeline()
        // Deactivate audio session safely
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#Preview {
    TalkToTextView(selectedFolder: nil)
}
