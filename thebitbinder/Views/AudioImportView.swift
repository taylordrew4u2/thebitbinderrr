//
//  AudioImportView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 1/4/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

/// Result of a single audio import attempt
struct AudioImportResult: Identifiable {
    let id = UUID()
    let filename: String
    let success: Bool
    let transcription: String?
    let confidence: Float?
    let error: String?
    let duration: TimeInterval?
    
    var confidenceDescription: String {
        guard let conf = confidence else { return "N/A" }
        let percentage = Int(conf * 100)
        if percentage >= 80 { return "High (\(percentage)%)" }
        if percentage >= 50 { return "Medium (\(percentage)%)" }
        return "Low (\(percentage)%)"
    }
}

/// View for importing audio files and transcribing them to jokes
struct AudioImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let selectedFolder: JokeFolder?
    
    @State private var showingFilePicker = false
    @State private var isProcessing = false
    @State private var processingCurrent = 0
    @State private var processingTotal = 0
    @State private var currentFilename = ""
    @State private var results: [AudioImportResult] = []
    @State private var showingResults = false
    @State private var authorizationStatus: String = ""
    
    private let transcriptionService = AudioTranscriptionService.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.blue.gradient)
                        
                        Text("Import Voice Memos")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 20)
                    
                    // Drop zone for drag and drop
                    DropZoneView { urls in
                        Task {
                            await processAudioFiles(urls)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Instructions for importing
                    VStack(alignment: .leading, spacing: 16) {
                        Label("How to Import Voice Memos", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundColor(AppTheme.Colors.primaryAction)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            ImportStepRow(number: 1, text: "Open the Voice Memos app")
                            ImportStepRow(number: 2, text: "Tap on the recording you want to import")
                            ImportStepRow(number: 3, text: "Tap the ••• (more) button")
                            ImportStepRow(number: 4, text: "Tap \"Save to Files\"")
                            ImportStepRow(number: 5, text: "Choose a location (e.g., On My iPhone)")
                            ImportStepRow(number: 6, text: "Come back here and tap \"Browse Files\" below")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.Colors.primaryAction.opacity(0.08))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Or browse files
                    VStack(spacing: 12) {
                        Text("— or —")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            Task {
                                await checkAuthorizationAndShowPicker()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text("Browse Files")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.Colors.primaryAction)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Info
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppTheme.Colors.primaryAction)
                        Text("Audio is transcribed to text and saved as a joke. The original audio file is not kept.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    if !authorizationStatus.isEmpty {
                        Text(authorizationStatus)
                            .font(.caption)
                            .foregroundColor(AppTheme.Colors.warning)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Import Voice Memos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                AudioDocumentPickerView { urls in
                    Task {
                        await processAudioFiles(urls)
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                AudioImportResultsView(results: results, onDone: {
                    showingResults = false
                    if results.contains(where: { $0.success }) {
                        dismiss()
                    }
                })
            }
            .overlay {
                if isProcessing {
                    ProcessingOverlay(
                        current: processingCurrent,
                        total: processingTotal,
                        filename: currentFilename
                    )
                }
            }
        }
    }
    
    private func checkAuthorizationAndShowPicker() async {
        let status = AudioTranscriptionService.authorizationStatus
        
        switch status {
        case .authorized:
            await MainActor.run { showingFilePicker = true }
        case .notDetermined:
            let newStatus = await AudioTranscriptionService.requestAuthorization()
            if newStatus == .authorized {
                await MainActor.run { showingFilePicker = true }
            } else {
                await MainActor.run {
                    authorizationStatus = "Speech recognition permission is required."
                }
            }
        case .denied, .restricted:
            await MainActor.run {
                authorizationStatus = "Speech recognition denied. Enable in Settings > Privacy > Speech Recognition."
            }
        @unknown default:
            break
        }
    }
    
    private func processAudioFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        
        await MainActor.run {
            isProcessing = true
            processingTotal = urls.count
            processingCurrent = 0
            results = []
        }
        
        for url in urls {
            await MainActor.run {
                currentFilename = url.lastPathComponent
            }
            
            do {
                let result = try await transcriptionService.transcribe(audioURL: url)
                
                let title = AudioTranscriptionService.generateTitle(from: result.transcription)
                let joke = Joke(content: result.transcription, title: title, folder: selectedFolder)
                
                await MainActor.run {
                    modelContext.insert(joke)
                    results.append(AudioImportResult(
                        filename: result.originalFilename,
                        success: true,
                        transcription: result.transcription,
                        confidence: result.confidence,
                        error: nil,
                        duration: result.duration
                    ))
                    processingCurrent += 1
                }
            } catch {
                await MainActor.run {
                    results.append(AudioImportResult(
                        filename: url.lastPathComponent,
                        success: false,
                        transcription: nil,
                        confidence: nil,
                        error: error.localizedDescription,
                        duration: nil
                    ))
                    processingCurrent += 1
                }
            }
            
            try? FileManager.default.removeItem(at: url)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save: \(error)")
        }
        
        await MainActor.run {
            isProcessing = false
            showingResults = true
        }
    }
}

// MARK: - Drop Zone View

struct DropZoneView: View {
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 40))
                .foregroundColor(isTargeted ? .blue : .gray)
            
            Text("Drag & Drop Voice Memos Here")
                .font(.headline)
                .foregroundColor(isTargeted ? .blue : .primary)
            
            Text("or use Share from Voice Memos app")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5))
        )
        .background(isTargeted ? AppTheme.Colors.primaryAction.opacity(0.1) : Color.clear)
        .cornerRadius(16)
        .dropDestination(for: URL.self) { urls, _ in
            let audioURLs = urls.filter { url in
                let ext = url.pathExtension.lowercased()
                return ["m4a", "mp3", "wav", "aac", "caf", "aiff"].contains(ext)
            }
            if !audioURLs.isEmpty {
                onDrop(audioURLs)
                return true
            }
            return false
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }
}

// MARK: - Document Picker

struct AudioDocumentPickerView: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let audioTypes: [UTType] = [
            .audio,
            .mpeg4Audio,
            .mp3,
            .wav,
            UTType(filenameExtension: "m4a") ?? .mpeg4Audio
        ]
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: audioTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        
        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
    }
}

// MARK: - Supporting Views

struct ProcessingOverlay: View {
    let current: Int
    let total: Int
    let filename: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Transcribing...")
                    .font(.headline)
                
                if total > 0 {
                    Text("\(current + 1) of \(total)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(filename)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(32)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }
}

struct AudioImportResultsView: View {
    let results: [AudioImportResult]
    let onDone: () -> Void
    
    var successCount: Int { results.filter { $0.success }.count }
    var failureCount: Int { results.filter { !$0.success }.count }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(successCount)")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.Colors.success)
                            Text("Imported")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if failureCount > 0 {
                            VStack(alignment: .trailing) {
                                Text("\(failureCount)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppTheme.Colors.error)
                                Text("Failed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                if successCount > 0 {
                    Section("Imported Jokes") {
                        ForEach(results.filter { $0.success }) { result in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.Colors.success)
                                    Text(result.filename)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                if let transcription = result.transcription {
                                    Text(transcription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                                Text("Confidence: \(result.confidenceDescription)")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                if failureCount > 0 {
                    Section("Failed") {
                        ForEach(results.filter { !$0.success }) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(AppTheme.Colors.error)
                                    Text(result.filename)
                                        .font(.subheadline)
                                }
                                if let error = result.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Import Step Row
struct ImportStepRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.Colors.primaryAction)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    AudioImportView(selectedFolder: nil)
}
