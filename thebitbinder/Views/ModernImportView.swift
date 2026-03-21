//
//  ModernImportView.swift
//  thebitbinder
//
//  Demonstrates the new import pipeline with review UI integration
//

import SwiftUI
import UniformTypeIdentifiers

struct ModernImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let selectedFolder: JokeFolder?
    
    @State private var importState: ImportState = .ready
    @State private var showingFilePicker = false
    @State private var showingReviewSheet = false
    @State private var pipelineResult: ImportPipelineResult?
    @State private var processingProgress = 0.0
    @State private var statusMessage = "Ready to import"
    @State private var errorMessage: String?
    
    private let importService = FileImportService.shared
    private let dataLogger = DataOperationLogger.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerSection
                
                Spacer()
                
                mainContent
                
                Spacer()
                
                actionButtons
            }
            .padding()
            .navigationTitle("Import Jokes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .pdf, .jpeg, .png, .heic, .text, .rtf,
                    UTType(filenameExtension: "doc")!,
                    UTType(filenameExtension: "docx")!
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .sheet(isPresented: $showingReviewSheet) {
                if let result = pipelineResult {
                    ImportReviewView(
                        importResult: result,
                        onComplete: { reviewResults in
                            Task {
                                await saveReviewedJokes(reviewResults)
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("Modern Import Pipeline")
                    .font(.title2.bold())
                
                Text("Advanced joke detection with review flow")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 16) {
            switch importState {
            case .ready:
                readyStateContent
            case .processing:
                processingStateContent
            case .completed(let result):
                completedStateContent(result)
            case .error(let error):
                errorStateContent(error)
            }
        }
    }
    
    private var readyStateContent: some View {
        VStack(spacing: 16) {
            Text("🎯 Smart Import Features")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "scissors", title: "Smart Splitting", description: "Prevents multiple jokes from being merged")
                FeatureRow(icon: "checkmark.seal", title: "Quality Validation", description: "Ensures one joke per entry")
                FeatureRow(icon: "eye", title: "Review Queue", description: "Manual review for uncertain imports")
                FeatureRow(icon: "iphone", title: "On-Device Processing", description: "Fast, private, no internet needed")
            }
            
            Text("Supported formats: PDF, Images, Word docs, Text files")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var processingStateContent: some View {
        VStack(spacing: 16) {
            ProgressView(value: processingProgress)
                .progressViewStyle(.linear)
            
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Processing with new pipeline...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func completedStateContent(_ result: ImportPipelineResult) -> some View {
        VStack(spacing: 16) {
            Text("✅ Import Complete")
                .font(.title2.bold())
                .foregroundColor(.green)
            
            VStack(spacing: 12) {
                ResultRow(
                    title: "Auto-Saved Jokes",
                    count: result.autoSavedJokes.count,
                    description: "High confidence, ready to use",
                    color: .green
                )
                
                ResultRow(
                    title: "Review Queue",
                    count: result.reviewQueueJokes.count,
                    description: "Need manual review",
                    color: .orange
                )
                
                ResultRow(
                    title: "Rejected Blocks",
                    count: result.rejectedBlocks.count,
                    description: "Not identified as jokes",
                    color: .gray
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            if result.reviewQueueJokes.isEmpty {
                Text("All jokes processed automatically!")
                    .foregroundColor(.green)
                    .font(.caption)
            } else {
                Text("Tap 'Review Import' to approve uncertain jokes")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func errorStateContent(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Import Failed")
                .font(.title2.bold())
                .foregroundColor(.red)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                importState = .ready
                errorMessage = nil
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            switch importState {
            case .ready:
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Select File to Import", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .processing:
                Button("Cancel") {
                    // Cancel processing if needed
                    importState = .ready
                }
                .buttonStyle(.bordered)
                
            case .completed(let result):
                HStack(spacing: 12) {
                    if !result.reviewQueueJokes.isEmpty {
                        Button {
                            showingReviewSheet = true
                        } label: {
                            Label("Review Import", systemImage: "eye")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    
                    Button {
                        if result.reviewQueueJokes.isEmpty {
                            // All done, dismiss
                            dismiss()
                        } else {
                            // Go directly to saving auto-saved jokes
                            Task {
                                await saveAutoSavedJokes()
                            }
                        }
                    } label: {
                        if result.reviewQueueJokes.isEmpty {
                            Label("Done", systemImage: "checkmark")
                        } else {
                            Label("Save Auto-Saved Only", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            case .error:
                EmptyView()
            }
        }
    }
    
    // MARK: - Import Processing
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await processFile(url: url)
            }
        case .failure(let error):
            importState = .error(error.localizedDescription)
        }
    }
    
    private func processFile(url: URL) async {
        await MainActor.run {
            importState = .processing
            statusMessage = "Analyzing file..."
            processingProgress = 0.1
        }
        
        do {
            // Start processing with progress updates
            await updateProgress(0.2, "Detecting file type...")
            
            let result = try await importService.importWithPipeline(from: url)
            
            await updateProgress(1.0, "Complete!")
            
            await MainActor.run {
                self.pipelineResult = result
                self.importState = .completed(result)
                
                // Auto-save high confidence jokes
                if !result.autoSavedJokes.isEmpty {
                    Task {
                        await saveHighConfidenceJokes(result.autoSavedJokes)
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                self.importState = .error(error.localizedDescription)
                self.errorMessage = error.localizedDescription
            }
            
            dataLogger.logError(error, operation: "MODERN_IMPORT", context: url.lastPathComponent)
        }
    }
    
    private func updateProgress(_ progress: Double, _ message: String) async {
        await MainActor.run {
            processingProgress = progress
            statusMessage = message
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000) // Brief delay for UI
    }
    
    // MARK: - Saving Operations
    
    private func saveHighConfidenceJokes(_ jokes: [ImportedJoke]) async {
        do {
            try await MainActor.run {
                try importService.saveApprovedJokes(jokes, to: modelContext)
            }
            
            dataLogger.logInfo("Auto-saved \(jokes.count) high-confidence jokes")
            
        } catch {
            dataLogger.logError(error, operation: "AUTO_SAVE_JOKES")
        }
    }
    
    private func saveAutoSavedJokes() async {
        guard let result = pipelineResult else { return }
        
        do {
            try await MainActor.run {
                try importService.saveApprovedJokes(result.autoSavedJokes, to: modelContext)
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                importState = .error(error.localizedDescription)
            }
        }
    }
    
    private func saveReviewedJokes(_ reviewResults: ImportReviewResults) async {
        do {
            try await MainActor.run {
                try importService.saveApprovedJokes(reviewResults.approvedJokes, to: modelContext)
                dismiss()
            }
            
            dataLogger.logInfo("Saved \(reviewResults.approvedJokes.count) reviewed jokes")
            
        } catch {
            await MainActor.run {
                importState = .error(error.localizedDescription)
            }
            
            dataLogger.logError(error, operation: "SAVE_REVIEWED_JOKES")
        }
    }
}

// MARK: - Import States

enum ImportState {
    case ready
    case processing
    case completed(ImportPipelineResult)
    case error(String)
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct ResultRow: View {
    let title: String
    let count: Int
    let description: String
    let color: Color
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(color)
        }
    }
}
