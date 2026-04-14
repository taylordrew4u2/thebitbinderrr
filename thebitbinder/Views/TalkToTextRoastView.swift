//
//  TalkToTextRoastView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 3/15/26.
//

import SwiftUI
import Speech
import AVFoundation
import AVFAudio

struct TalkToTextRoastView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    let target: RoastTarget
    
    @State private var transcribedText = ""
    @State private var isRecording = false
    @State private var permissionStatus: PermissionStatus = .notDetermined
    @State private var showingPermissionAlert = false
    @State private var errorMessage: String?
    @State private var targetInvalidated = false
    
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    /// Safe access to target name
    private var safeTargetName: String {
        target.isValid ? target.name : "Target"
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
    
    private let accentColor = Color.blue
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                         Circle()
                             .fill(isRecording ? Color.red.opacity(0.15) : accentColor.opacity(0.1))
                             .frame(width: 100, height: 100)
                             .scaleEffect(isRecording ? 1.1 : 1.0)
                             .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                         
                         Image(systemName: isRecording ? "waveform" : "mic.fill")
                             .font(.largeTitle)
                             .foregroundColor(isRecording ? .red : accentColor)
                             .symbolEffect(.variableColor, isActive: isRecording)
                     }
                     
                     Text(isRecording ? "Listening..." : "Ready")
                         .font(.title3)
                         .fontWeight(.semibold)
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
                            .foregroundColor(accentColor)
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
                                .foregroundColor(.primary) // Ensure text is visible in light/dark mode
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
                    .tint(isRecording ? .red : accentColor)
                    .controlSize(.large)
                    .disabled(permissionStatus == .denied)
                    
                    // Save button (only show when there's text and not recording)
                    if !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                        Button {
                            saveRoast()
                        } label: {
                            Label("Save as Roast", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.large)
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
        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        
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
        
        speechRecognizer.stopTranscribing()
        errorMessage = nil
        isRecording = true
        speechRecognizer.startTranscribing()
    }
    
    private func stopRecording() {
        isRecording = false
        speechRecognizer.stopTranscribing()
    }
    
    private func saveRoast() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Safety check - ensure target is still valid
        guard target.isValid else {
            errorMessage = "Target was deleted. Cannot save roast."
            return
        }
        
        let newJoke = RoastJoke(
            content: text,
            target: target
        )
        
        modelContext.insert(newJoke)
        target.dateModified = Date()
        
        do {
            try modelContext.save()
            #if DEBUG
            print(" [TalkToTextRoastView] Roast saved for '\(target.name)' (id: \(newJoke.id))")
            #endif
            dismiss()
        } catch {
            #if DEBUG
            print(" [TalkToTextRoastView] Failed to save: \(error)")
            #endif
            errorMessage = "Could not save roast: \(error.localizedDescription)"
        }
    }
}
