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
    let saveToBrainstorm: Bool
    
    @State private var transcribedText = ""
    @State private var isRecording = false
    @State private var permissionStatus: PermissionStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var errorMessage: String?
    @State private var showSavedConfirmation = false
    @State private var isSaving = false
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    init(selectedFolder: JokeFolder?, saveToBrainstorm: Bool = false) {
        self.selectedFolder = selectedFolder
        self.saveToBrainstorm = saveToBrainstorm
    }
    
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
                // Header - Mic icon with animation
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.1))
                            .frame(width: 100, height: 100)
                            .scaleEffect(isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isRecording ? .red : .accentColor)
                            .symbolEffect(.variableColor, isActive: isRecording)
                    }
                    
                    Text(isRecording ? "Listening..." : "Ready")
                        .font(.title3)
                        .fontWeight(.semibold)
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
                                .foregroundColor(.accentColor)
                            }
                        }
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(UIColor.secondarySystemBackground))
                            
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
                            .foregroundColor(.red)
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
                            Label(isRecording ? "Stop" : "Start Recording",
                                  systemImage: isRecording ? "stop.fill" : "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRecording ? .red : .accentColor)
                        .controlSize(.large)
                        .disabled(permissionStatus == .denied)
                        
                        // Save button (only show when there's text and not recording)
                        if !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                            Button {
                                saveItem()
                            } label: {
                                HStack(spacing: 10) {
                                    if isSaving {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    Text(saveToBrainstorm ? "Save Idea" : "Save Joke")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(saveToBrainstorm ? .blue : .blue)
                            .controlSize(.large)
                            .disabled(isSaving)
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
                .onDisappear {
                    // Ensure audio pipeline is fully torn down when leaving this view
                    if isRecording {
                        isRecording = false
                    }
                    speechRecognizer.stopTranscribing()
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
                    Text("Microphone and Speech Recognition permissions are required for Talk-to-Text Joke. Please enable them in Settings.")
                }
                .onChange(of: speechRecognizer.transcribedText) { _, newValue in
                    transcribedText = newValue
                }
                .onChange(of: speechRecognizer.error) { _, newValue in
                    errorMessage = newValue
                }
                .overlay {
                    if showSavedConfirmation {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(saveToBrainstorm ? .blue : .blue)
                            Text(saveToBrainstorm ? "Idea Saved!" : "Joke Saved!")
                                .font(.headline)
                        }
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showSavedConfirmation)
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
        // If permissions haven't been determined yet, request them and auto-start on success
        if permissionStatus == .notDetermined {
            Task {
                await requestPermissions()
                // After permissions are resolved, start recording automatically if granted
                if permissionStatus == .authorized {
                    beginRecordingSession()
                }
            }
            return
        }
        
        guard permissionStatus == .authorized else {
            showingPermissionAlert = true
            return
        }
        
        beginRecordingSession()
    }
    
    /// Actually kicks off the speech recognition session (call only when permissions are confirmed).
    private func beginRecordingSession() {
        errorMessage = nil
        isRecording = true
        speechRecognizer.startTranscribing()
    }
    
    private func stopRecording() {
        isRecording = false
        speechRecognizer.stopTranscribing()
    }
    
    private func saveItem() {
        if saveToBrainstorm {
            saveBrainstormIdea()
        } else {
            saveJoke()
        }
    }
    
    private func saveBrainstormIdea() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Cannot save an empty idea."
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        // Create the brainstorm idea
        let idea = BrainstormIdea(
            content: text,
            colorHex: BrainstormIdea.randomColor(),
            isVoiceNote: true
        )
        
        modelContext.insert(idea)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [TalkToTextView] Brainstorm idea saved — id: \(idea.id)")
            #endif
            
            isSaving = false
            showSavedConfirmation = true
            
            // Brief confirmation then dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } catch {
            isSaving = false
            #if DEBUG
            print(" [TalkToTextView] Failed to save brainstorm idea: \(error)")
            #endif
            errorMessage = "Could not save idea: \(error.localizedDescription)"
        }
    }
    
    private func saveJoke() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = "Cannot save an empty joke."
            return
        }
        
        isSaving = true
        errorMessage = nil
        
        // Create the joke
        let title = generateTitle(from: text)
        let newJoke = Joke(
            content: text,
            title: title,
            folder: selectedFolder
        )
        
        modelContext.insert(newJoke)
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [TalkToTextView] Joke saved — id: \(newJoke.id), title: \"\(title)\", folder: \(selectedFolder?.name ?? "none")")
            #endif
            
            // Notify other views that the joke database changed (matches AddJokeView pattern)
            NotificationCenter.default.post(name: .jokeDatabaseDidChange, object: nil)
            
            isSaving = false
            showSavedConfirmation = true
            
            // Brief confirmation then dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
            }
        } catch {
            isSaving = false
            #if DEBUG
            print(" [TalkToTextView] Failed to save joke: \(error)")
            #endif
            errorMessage = "Could not save joke: \(error.localizedDescription)"
        }
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
    /// Guard against overlapping restart attempts
    private var isRestarting = false
    /// Observer for memory warnings
    private var memoryWarningObserver: NSObjectProtocol?
    /// Observer for audio session interruptions (phone calls, Siri, etc.)
    private var interruptionObserver: NSObjectProtocol?
    /// Tracks consecutive engine-start failures to avoid infinite retry loops
    private var consecutiveStartFailures = 0
    private let maxConsecutiveStartFailures = 3
    /// Generation counter — incremented on every full stop / reset to invalidate stale async callbacks
    private var sessionGeneration = 0
    
    init() {
        // Stop the audio pipeline on memory warnings — AVAudioEngine + speech
        // recognition buffers are the single largest memory consumer in the app.
        // The OS sends this notification before killing with code 9.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            guard self.shouldBeRunning else { return }
            print(" [SpeechRecognizer] Memory warning — stopping to free resources")
            // Preserve transcription so user doesn't lose work
            self.accumulatedText = self.transcribedText
            self.shouldBeRunning = false
            self.tearDownAudioPipeline(deactivateSession: true)
            self.isTranscribing = false
            self.error = "Recording paused due to low memory. Your text is preserved — tap Start to resume."
        }
        
        // Handle audio session interruptions (phone calls, Siri, etc.)
        // so recognition can resume automatically after the interruption ends.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard self.shouldBeRunning else { return }
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            
            switch type {
            case .began:
                print(" [SpeechRecognizer] Audio interrupted — preserving text")
                self.accumulatedText = self.transcribedText
                self.tearDownAudioPipeline(deactivateSession: false)
            case .ended:
                print(" [SpeechRecognizer] Interruption ended — restarting")
                if self.shouldBeRunning {
                    self.isRestarting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.startRecognitionSession()
                    }
                }
            @unknown default:
                break
            }
        }
    }
    
    func startTranscribing() {
        // Don't reset text — preserve anything already transcribed
        error = nil
        shouldBeRunning = true
        isRestarting = false
        accumulatedText = transcribedText
        consecutiveStartFailures = 0
        
        startRecognitionSession()
    }
    
    /// Tears down any active audio pipeline without deactivating the audio session.
    /// Use this before `startTranscribing()` to avoid the rapid setActive(false)/setActive(true)
    /// toggle that causes iOS to silently reject the next recognition request.
    func resetForNewSession() {
        shouldBeRunning = false
        sessionGeneration += 1
        tearDownAudioPipeline(deactivateSession: false)
        accumulatedText = ""
        isRestarting = false
        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = false
        }
    }
    
    /// Sets up a reliable audio session with fallback configurations.
    /// Tries multiple strategies to ensure audio is configured correctly.
    private func configureAudioSessionWithFallbacks() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Strategy 1: Preferred configuration for speech recognition.
        // Using `.default` mode (NOT `.measurement`) so iOS applies its built-in
        // AGC, noise suppression, and echo cancellation — critical for getting
        // clean audio that the speech recognizer can actually transcribe.
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            print(" [SpeechRecognizer] Preferred audio config failed: \(error)")
        }
        
        // Strategy 2: Without Bluetooth options (some devices reject Bluetooth combo)
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            return true
        } catch {
            print(" [SpeechRecognizer] Audio config without Bluetooth failed: \(error)")
        }
        
        // Strategy 3: Minimal record-only configuration
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            return true
        } catch {
            print(" [SpeechRecognizer] Minimal audio config failed: \(error)")
        }
        
        return false
    }
    
    /// Internal: starts or restarts one speech recognition session.
    private func startRecognitionSession() {
        // Prevent overlapping restart attempts that can stack sessions
        guard !isRestarting else { return }
        isRestarting = true
        
        // Clean up any previous session without clearing state.
        // Keep the audio session active across restarts — toggling it off/on
        // causes iOS to reassign the audio route, which cancels the next request.
        tearDownAudioPipeline(deactivateSession: false)
        
        guard shouldBeRunning else {
            isRestarting = false
            return
        }
        
        // Check if speech recognizer is available. On cold launch, `isAvailable`
        // can briefly return false while the system initializes — retry a few
        // times with short delays before giving up.
        guard let speechRecognizer = speechRecognizer else {
            isRestarting = false
            DispatchQueue.main.async { [weak self] in
                self?.error = "Speech recognition is not supported on this device."
                self?.isTranscribing = false
            }
            return
        }
        
        if !speechRecognizer.isAvailable {
            isRestarting = false
            // Retry up to 3 times with increasing delay — handles cold-launch
            // and post-interruption race where isAvailable flips true shortly.
            if consecutiveStartFailures < maxConsecutiveStartFailures && shouldBeRunning {
                consecutiveStartFailures += 1
                let delay = 0.3 * Double(consecutiveStartFailures)
                print(" [SpeechRecognizer] Not yet available — retrying in \(delay)s (attempt \(consecutiveStartFailures))")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.startRecognitionSession()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.error = "Speech recognition is not available right now. Please check your internet connection and try again."
                    self?.isTranscribing = false
                }
            }
            return
        }
        
        // Configure audio session — use multiple fallback strategies
        guard configureAudioSessionWithFallbacks() else {
            isRestarting = false
            DispatchQueue.main.async { [weak self] in
                self?.error = "Cannot configure audio system. Please check audio settings and try again."
                self?.isTranscribing = false
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
            isRestarting = false
            DispatchQueue.main.async { [weak self] in
                self?.error = "Audio input format is invalid. Please check your microphone."
                self?.isTranscribing = false
            }
            return
        }
        
        // Install audio tap — use autoreleasepool to release each buffer promptly
        // and only forward if the request is still alive (avoids appending to a
        // finished/cancelled request).
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            autoreleasepool {
                self?.recognitionRequest?.append(buffer)
            }
        }
        
        // Start recognition task — capture self weakly in the result handler
        // AND in every inner DispatchQueue closure to avoid retain cycles.
        let generation = sessionGeneration
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.sessionGeneration == generation else { return }
            
            var isFinal = false
            
            if let result = result {
                isFinal = result.isFinal
                let newText = result.bestTranscription.formattedString
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
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
                let isRecognizerUnavailable = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1601
                let isNetworkError = nsError.code == -1001 || nsError.code == -1004 // Network timeouts
                
                print(" [SpeechRecognizer] Recognition error — domain: \(nsError.domain), code: \(nsError.code), msg: \(error.localizedDescription)")
                
                if isCancelled {
                    // User explicitly stopped — do nothing
                    return
                }
                
                if isRecognizerUnavailable {
                    // Speech recognizer service is unavailable (e.g., network issue, service down)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.accumulatedText = self.transcribedText
                        self.error = "Speech service unavailable. Your text has been preserved."
                        self.isTranscribing = false
                    }
                    return
                }
                
                if isNetworkError {
                    // Network connectivity issue
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.error = "Network connection issue. Your text has been preserved — tap Start to retry."
                    }
                    return
                }
                
                if isTimeout || isFinal {
                    // Speech recognition timed out (~60s) or finished —
                    // save what we have and restart automatically
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.accumulatedText = self.transcribedText
                        if self.shouldBeRunning {
                            // Brief delay with exponential backoff for retries
                            let delaySeconds = Double(self.consecutiveStartFailures) * 0.3
                            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, delaySeconds)) { [weak self] in
                                self?.startRecognitionSession()
                            }
                        }
                    }
                    return
                }
                
                // Real error — show it with recovery option
                DispatchQueue.main.async { [weak self] in
                    self?.error = "Recognition error: \(error.localizedDescription). Tap Start to try again."
                    self?.isTranscribing = false
                }
                return
            }
            
            // If result is final (e.g. recognizer decided speech ended), auto-restart
            if isFinal {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.accumulatedText = self.transcribedText
                    if self.shouldBeRunning {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.startRecognitionSession()
                        }
                    }
                }
            }
        }
        
        // Start audio engine with enhanced error recovery
        do {
            engine.prepare()
            try engine.start()
            consecutiveStartFailures = 0
            isRestarting = false
            DispatchQueue.main.async { [weak self] in
                self?.isTranscribing = true
            }
            print(" [SpeechRecognizer] Audio engine started successfully")
        } catch {
            consecutiveStartFailures += 1
            let errorMsg = "Audio engine failed to start: \(error.localizedDescription)"
            print(" [SpeechRecognizer] \(errorMsg) (attempt \(consecutiveStartFailures))")
            tearDownAudioPipeline()
            isRestarting = false
            
            if consecutiveStartFailures < maxConsecutiveStartFailures && shouldBeRunning {
                // Retry with exponential backoff
                let delaySeconds = Double(consecutiveStartFailures) * 0.5
                DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                    self?.startRecognitionSession()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.error = "Audio recording failed. Please restart the app and try again."
                    self?.isTranscribing = false
                }
            }
        }
    }
    
    func stopTranscribing() {
        shouldBeRunning = false
        sessionGeneration += 1
        tearDownAudioPipeline(deactivateSession: true)
        accumulatedText = ""
        DispatchQueue.main.async { [weak self] in
            self?.isTranscribing = false
        }
    }
    
    /// Tears down audio engine and recognition without resetting user-facing state.
    /// - Parameter deactivateSession: If `true` (full stop), deactivates the audio session
    ///   and cancels the task. If `false` (restart), keeps the session active and calls
    ///   `finish()` so iOS doesn't treat the next request as a rapid retry and cancel it.
    private func tearDownAudioPipeline(deactivateSession: Bool = true) {
        // 1. Stop the audio engine first so no more buffers are appended
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        
        // 2. End audio on the request so the recognition task can finish
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // 3. During a restart, let the task finish gracefully with buffered audio.
        //    On a full stop, cancel immediately.
        if deactivateSession {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionTask = nil
        
        // 4. Only deactivate the audio session on a full stop — keeping it active
        //    across restarts prevents iOS from reassigning the audio route and
        //    immediately cancelling the next recognition request.
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        shouldBeRunning = false
        tearDownAudioPipeline(deactivateSession: true)
    }
}

#Preview {
    TalkToTextView(selectedFolder: nil, saveToBrainstorm: false)
}
