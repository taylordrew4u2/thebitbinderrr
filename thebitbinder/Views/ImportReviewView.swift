//
//  ImportReviewView.swift
//  thebitbinder
//
//  SwiftUI interface for reviewing imported jokes
//

import SwiftUI

struct ImportReviewView: View {
    @StateObject private var viewModel = ImportReviewViewModel()
    @State private var showingCompletionSheet = false
    @Environment(\.dismiss) private var dismiss
    
    let importResult: ImportPipelineResult
    let onComplete: (ImportReviewResults) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !viewModel.reviewItems.isEmpty {
                    // Progress indicator
                    progressHeader
                    
                    Divider()
                    
                    // Main review content
                    ScrollView {
                        if let currentItem = viewModel.currentItem {
                            ImportReviewCardView(
                                item: currentItem,
                                onUpdate: { title, body, tags in
                                    viewModel.updateCurrentItemText(title: title, body: body, tags: tags)
                                }
                            )
                            .padding()
                        }
                    }
                    
                    Divider()
                    
                    // Action buttons
                    actionButtons
                    
                    // Navigation controls
                    navigationControls
                    
                } else {
                    ContentUnavailableView(
                        "No Items to Review",
                        systemImage: "checkmark.circle",
                        description: Text("All jokes have been automatically processed.")
                    )
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Approve All", action: viewModel.approveAll)
                        Button("Reject All", action: viewModel.rejectAll)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCompletionSheet) {
                ReviewCompletionView(
                    results: viewModel.getReviewResults(),
                    onSave: { results in
                        onComplete(results)
                        dismiss()
                    },
                    onCancel: {
                        showingCompletionSheet = false
                    }
                )
            }
            .onChange(of: viewModel.allItemsReviewed) { _, allReviewed in
                if allReviewed {
                    showingCompletionSheet = true
                }
            }
        }
        .onAppear {
            viewModel.loadReviewItems(from: importResult)
        }
    }
    
    // MARK: - View Components
    
    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Import Review")
                    .font(.headline)
                
                Spacer()
                
                Text(viewModel.progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: Double(viewModel.currentIndex + 1), total: Double(viewModel.reviewItems.count))
            
            Text(viewModel.summaryText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.rejectCurrentItem()
            } label: {
                Label("Reject", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            
            Button {
                viewModel.markForSplitting()
            } label: {
                Label("Split", systemImage: "scissors")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.bordered)
            
            Button {
                viewModel.approveCurrentItem()
            } label: {
                Label("Approve", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
    }
    
    private var navigationControls: some View {
        HStack {
            Button {
                viewModel.goToPrevious()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(!viewModel.hasPrevious)
            
            Spacer()
            
            Button("Finish Review") {
                showingCompletionSheet = true
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
            
            Button {
                viewModel.goToNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(!viewModel.hasNext)
        }
        .padding()
    }
}

// MARK: - Individual Item Review Card

struct ImportReviewCardView: View {
    let item: ImportReviewItem
    let onUpdate: (String, String, [String]) -> Void
    
    @State private var editedTitle: String
    @State private var editedBody: String
    @State private var editedTags: [String]
    @State private var newTag = ""
    
    init(item: ImportReviewItem, onUpdate: @escaping (String, String, [String]) -> Void) {
        self.item = item
        self.onUpdate = onUpdate
        _editedTitle = State(initialValue: item.editedTitle)
        _editedBody = State(initialValue: item.editedBody)
        _editedTags = State(initialValue: item.editedTags)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Import info
            importInfoSection
            
            Divider()
            
            // Editing section
            editingSection
            
            // Issues section
            if !item.originalJoke.issuesDescription.isEmpty {
                Divider()
                issuesSection
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onChange(of: editedTitle) { _, newValue in
            onUpdate(newValue, editedBody, editedTags)
        }
        .onChange(of: editedBody) { _, newValue in
            onUpdate(editedTitle, newValue, editedTags)
        }
        .onChange(of: editedTags) { _, newValue in
            onUpdate(editedTitle, editedBody, newValue)
        }
    }
    
    private var importInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Import Info")
                    .font(.headline)
                
                Spacer()
                
                confidenceBadge
            }
            
            HStack {
                Label("Page \(item.originalJoke.sourceMetadata.pageNumber)", systemImage: "doc.text")
                Spacer()
                Label("\(item.originalJoke.extractionMethod.rawValue)", systemImage: "wand.and.rays")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
    
    private var confidenceBadge: some View {
        Text(item.originalJoke.confidence.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
    
    private var confidenceColor: Color {
        switch item.originalJoke.confidence {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }
    
    private var editingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Joke")
                .font(.headline)
            
            // Title field
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption.bold())
                TextField("Enter joke title (optional)", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Body field
            VStack(alignment: .leading, spacing: 4) {
                Text("Body")
                    .font(.caption.bold())
                TextField("Joke content", text: $editedBody, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...10)
            }
            
            // Tags section
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.caption.bold())
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(editedTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .font(.caption)
                            Button {
                                editedTags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                
                HStack {
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addNewTag()
                        }
                    
                    Button("Add", action: addNewTag)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issues Found")
                .font(.headline)
                .foregroundColor(.orange)
            
            Text(item.originalJoke.issuesDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private func addNewTag() {
        let trimmedTag = newTag.trimmingCharacters(in: .whitespaces)
        if !trimmedTag.isEmpty && !editedTags.contains(trimmedTag) {
            editedTags.append(trimmedTag)
            newTag = ""
        }
    }
}

// MARK: - Review Completion View

struct ReviewCompletionView: View {
    let results: ImportReviewResults
    let onSave: (ImportReviewResults) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Review Complete")
                    .font(.largeTitle.bold())
                
                VStack(spacing: 16) {
                    resultRow(title: "Approved Jokes", count: results.approvedJokes.count, color: .green)
                    resultRow(title: "Rejected Jokes", count: results.rejectedJokes.count, color: .red)
                    resultRow(title: "Need Splitting", count: results.jokesNeedingSplitting.count, color: .orange)
                    
                    if !results.pendingJokes.isEmpty {
                        resultRow(title: "Still Pending", count: results.pendingJokes.count, color: .gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                if !results.pendingJokes.isEmpty {
                    Text("⚠️ Some jokes are still pending review")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button("Save Results") {
                        onSave(results)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!results.isComplete)
                    
                    Button("Continue Reviewing", action: onCancel)
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Import Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
    
    private func resultRow(title: String, count: Int, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(color)
        }
    }
}

// MARK: - ImportedJoke Extension

extension ImportedJoke {
    var issuesDescription: String {
        switch validationResult {
        case .singleJoke:
            if confidence == .low {
                return "Low confidence due to OCR quality or structural issues"
            }
            return ""
        case .requiresReview(let reasons):
            return reasons.joined(separator: "\n• ")
        case .multipleJokes(_, let reasons):
            return "May contain multiple jokes:\n• " + reasons.joined(separator: "\n• ")
        case .notAJoke:
            return "Content may not be joke material"
        }
    }
}