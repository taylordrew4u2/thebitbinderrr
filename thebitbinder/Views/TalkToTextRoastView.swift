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
    
    private let accentColor = AppTheme.Colors.roastAccent
    
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
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isRecording ? .red : accentColor)
                            .symbolEffect(.variableColor, isActive: isRecording)
                    }
                    
                    Text(isRecording ? "Listening..." : "Roast Talk-to-Text")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Recording for \(target.name)")
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
                            .foregroundColor(accentColor)
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
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
                        .foregroundColor(AppTheme.Colors.recordingsAccent)
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
                        .background(isRecording ? AppTheme.Colors.recordingsAccent : accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(permissionStatus == .denied)
                    
                    // Save button (only show when there's text and not recording)
                    if !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                        Button {
                            saveRoast()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                Text("Save as Roast")
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
        
        let newJoke = RoastJoke(
            content: text,
            target: target
        )
        
        modelContext.insert(newJoke)
        target.dateModified = Date()
        
        do {
            try modelContext.save()
            #if DEBUG
            print("✅ [TalkToTextRoastView] Roast saved for '\(target.name)' (id: \(newJoke.id))")
            #endif
            dismiss()
        } catch {
            #if DEBUG
            print("❌ [TalkToTextRoastView] Failed to save: \(error)")
            #endif
            errorMessage = "Could not save roast: \(error.localizedDescription)"
        }
    }
}
