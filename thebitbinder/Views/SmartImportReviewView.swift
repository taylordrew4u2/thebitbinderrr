//
//  SmartImportReviewView.swift
//  thebitbinder
//
//  Interactive joke-by-joke import review with swipe cards.
//  Accept / Reject / Edit / Send to Brainstorm
//

import SwiftUI
import SwiftData

struct SmartImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ImportReviewViewModel()
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    let importResult: ImportPipelineResult
    let selectedFolder: JokeFolder?
    let onComplete: (() -> Void)?
    
    @State private var showingEditSheet = false
    @State private var dragOffset: CGSize = .zero
    @State private var showingSaveConfirmation = false
    @State private var savedCount = 0
    @State private var brainstormCount = 0
    
    init(importResult: ImportPipelineResult, selectedFolder: JokeFolder? = nil, onComplete: (() -> Void)? = nil) {
        self.importResult = importResult
        self.selectedFolder = selectedFolder
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress bar
                    progressSection
                    
                    // Gemini rate-limit error banner (shown when daily limit is hit)
                    if let rateLimitErr = viewModel.rateLimitError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.white)
                            Text(rateLimitErr.localizedDescription ?? "Gemini daily limit reached.")
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange)
                    }
                    
                    if viewModel.reviewItems.isEmpty {
                        emptyState
                    } else if let current = viewModel.currentItem {
                        // Card area
                        Spacer()
                        jokeCard(current)
                            .offset(dragOffset)
                            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                            .gesture(swipeGesture)
                            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: dragOffset)
                        Spacer()
                        
                        // Action buttons
                        actionButtonRow
                        
                        // Navigation
                        navigationRow
                    } else {
                        // All reviewed
                        allReviewedState
                    }
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                roastMode ? AnyShapeStyle(AppTheme.Colors.roastSurface) : AnyShapeStyle(AppTheme.Colors.paperCream),
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("✅ Approve All Remaining") { viewModel.approveAll() }
                        Button("❌ Reject All Remaining") { viewModel.rejectAll() }
                        Divider()
                        Button("Save & Finish") {
                            Task {
                                await finishAndSave()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                if let current = viewModel.currentItem {
                    editSheet(for: current)
                }
            }
            .alert("Import Complete", isPresented: $showingSaveConfirmation) {
                Button("Done") {
                    onComplete?()
                    dismiss()
                }
            } message: {
                Text("Saved \(savedCount) joke\(savedCount == 1 ? "" : "s") and sent \(brainstormCount) idea\(brainstormCount == 1 ? "" : "s") to Brainstorm.")
            }
        }
        .onAppear {
            viewModel.loadAllItems(from: importResult)
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(spacing: 8) {
            // Counts
            HStack(spacing: 16) {
                Text(viewModel.summaryText)
                    .font(.caption)
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                Spacer()
                // Gemini daily budget indicator
                Label("\(viewModel.geminiRequestsRemaining) AI left today", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundColor(
                        viewModel.geminiRequestsRemaining < 50
                            ? .orange
                            : (roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    )
                Text(viewModel.progressText)
                    .font(.caption.bold())
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.textPrimary)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(roastMode ? Color.white.opacity(0.1) : AppTheme.Colors.paperDeep)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
                        .frame(width: geo.size.width * progressFraction)
                        .animation(.easeInOut(duration: 0.3), value: progressFraction)
                }
            }
            .frame(height: 6)
            
            // Mini dot indicators for reviewed status
            miniDotIndicators
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var progressFraction: CGFloat {
        guard !viewModel.reviewItems.isEmpty else { return 0 }
        let reviewed = viewModel.reviewItems.filter { $0.action != .pending }.count
        return CGFloat(reviewed) / CGFloat(viewModel.reviewItems.count)
    }
    
    private var miniDotIndicators: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.reviewItems.enumerated()), id: \.element.id) { index, item in
                    Circle()
                        .fill(dotColor(for: item, isActive: index == viewModel.currentIndex))
                        .frame(width: index == viewModel.currentIndex ? 10 : 6,
                               height: index == viewModel.currentIndex ? 10 : 6)
                        .onTapGesture { viewModel.goToItem(at: index) }
                }
            }
        }
    }
    
    private func dotColor(for item: ImportReviewItem, isActive: Bool) -> Color {
        if isActive {
            return roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand
        }
        switch item.action {
        case .approved: return .green
        case .rejected: return .red.opacity(0.5)
        case .sendToBrainstorm: return .yellow
        case .needsSplitting: return .orange
        case .pending: return roastMode ? .white.opacity(0.2) : .gray.opacity(0.3)
        }
    }
    
    // MARK: - Joke Card
    
    private func jokeCard(_ item: ImportReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Confidence badge
            HStack {
                confidenceBadge(item.originalJoke.confidence)
                Spacer()
                Text("Page \(item.originalJoke.sourceMetadata.pageNumber)")
                    .font(.caption)
                    .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
            }
            
            // Title
            if !item.editedTitle.isEmpty {
                Text(item.editedTitle)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
            }
            
            // Body
            ScrollView {
                Text(item.editedBody)
                    .font(.system(size: 16, design: .serif))
                    .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Tags
            if !item.editedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.editedTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(
                                        roastMode ? AppTheme.Colors.roastAccent.opacity(0.2) : AppTheme.Colors.brand.opacity(0.1)
                                    )
                                )
                                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
                        }
                    }
                }
            }
            
            // Swipe hints
            HStack {
                Label("Reject", systemImage: "arrow.left")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.5))
                Spacer()
                Label("Accept", systemImage: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.green.opacity(0.5))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: 400)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                .shadow(radius: abs(dragOffset.width) > 30 ? 12 : 6, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .inset(by: 1.5)
                .stroke(swipeBorderColor, lineWidth: 3)
        )
        .overlay(alignment: .center) {
            // Swipe feedback overlay
            let absWidth = Double(abs(dragOffset.width))
            if absWidth > 60 {
                Text(dragOffset.width > 0 ? "✅" : "❌")
                    .font(.system(size: 60))
                    .opacity(min(absWidth / 120.0, 1.0))
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var swipeColor: Color {
        if dragOffset.width > 30 { return .green }
        if dragOffset.width < -30 { return .red }
        return .clear
    }
    
    private var swipeBorderColor: Color {
        let opacity = min(Double(abs(dragOffset.width)) / 100.0, 0.8)
        if dragOffset.width > 30 { return .green.opacity(opacity) }
        if dragOffset.width < -30 { return .red.opacity(opacity) }
        return .clear
    }
    
    private var swipeOpacity: Double {
        min(Double(abs(dragOffset.width)) / 100.0, 0.8)
    }
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    // Swipe right → Accept
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: 500, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.approveCurrentItem()
                        dragOffset = .zero
                    }
                } else if value.translation.width < -threshold {
                    // Swipe left → Reject
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset = CGSize(width: -500, height: 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.rejectCurrentItem()
                        dragOffset = .zero
                    }
                } else {
                    // Snap back
                    withAnimation(.interactiveSpring()) {
                        dragOffset = .zero
                    }
                }
            }
    }
    
    private func confidenceBadge(_ confidence: ImportConfidence) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(confidenceColor(confidence))
                .frame(width: 8, height: 8)
            Text(confidence.rawValue.capitalized)
                .font(.caption2.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(confidenceColor(confidence).opacity(0.15)))
        .foregroundColor(confidenceColor(confidence))
    }
    
    private func confidenceColor(_ confidence: ImportConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonRow: some View {
        HStack(spacing: 12) {
            // Reject
            Button {
                withAnimation { viewModel.rejectCurrentItem() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                    Text("Skip")
                        .font(.caption2)
                }
                .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity)
            
            // Send to Brainstorm
            Button {
                withAnimation { viewModel.sendCurrentToBrainstorm() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 32))
                    Text("Brainstorm")
                        .font(.caption2)
                }
                .foregroundColor(.yellow)
            }
            .frame(maxWidth: .infinity)
            
            // Edit
            Button {
                showingEditSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 32))
                    Text("Edit")
                        .font(.caption2)
                }
                .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
            }
            .frame(maxWidth: .infinity)
            
            // Accept
            Button {
                withAnimation { viewModel.approveCurrentItem() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                    Text("Accept")
                        .font(.caption2)
                }
                .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.surfaceElevated)
                .shadow(color: .black.opacity(0.05), radius: 4, y: -2)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Navigation Row
    
    private var navigationRow: some View {
        HStack {
            Button {
                viewModel.goToPrevious()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline)
            }
            .disabled(!viewModel.hasPrevious)
            
            Spacer()
            
            Button("Save & Finish") {
                Task {
                    await finishAndSave()
                }
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
            
            Spacer()
            
            Button {
                viewModel.goToNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .font(.subheadline)
            }
            .disabled(!viewModel.hasNext)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
    
    // MARK: - States
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("Nothing to Review")
                .font(.title2.bold())
            Text("No jokes were detected in this file.")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var allReviewedState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("All Reviewed!")
                .font(.title2.bold())
            Text(viewModel.summaryText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Save & Finish") {
                Task {
                    await finishAndSave()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.brand)
            .controlSize(.large)
            
            Spacer()
        }
    }
    
    // MARK: - Edit Sheet
    
    private func editSheet(for item: ImportReviewItem) -> some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Joke title (optional)", text: Binding(
                        get: { viewModel.currentItem?.editedTitle ?? "" },
                        set: { newTitle in
                            viewModel.updateCurrentItemText(
                                title: newTitle,
                                body: viewModel.currentItem?.editedBody ?? "",
                                tags: viewModel.currentItem?.editedTags ?? []
                            )
                        }
                    ))
                }
                
                Section("Content") {
                    TextField("Joke body", text: Binding(
                        get: { viewModel.currentItem?.editedBody ?? "" },
                        set: { newBody in
                            viewModel.updateCurrentItemText(
                                title: viewModel.currentItem?.editedTitle ?? "",
                                body: newBody,
                                tags: viewModel.currentItem?.editedTags ?? []
                            )
                        }
                    ), axis: .vertical)
                    .lineLimit(5...15)
                }
                
                Section("Original Source Text") {
                    Text(item.originalJoke.rawSourceText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Joke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingEditSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Save Logic
    
    private func finishAndSave() async {
        let results = viewModel.getReviewResults()
        
        do {
            // Insert approved jokes
            for importedJoke in results.approvedJokes {
                let joke = Joke(content: importedJoke.body, title: importedJoke.title ?? "")
                joke.dateCreated = importedJoke.sourceMetadata.importTimestamp
                joke.dateModified = Date()
                joke.tags = importedJoke.tags
                joke.folder = selectedFolder
                joke.importSource = importedJoke.sourceMetadata.fileName
                joke.importConfidence = importedJoke.confidence.rawValue
                joke.importTimestamp = importedJoke.sourceMetadata.importTimestamp
                modelContext.insert(joke)
            }
            
            // Insert brainstorm items
            for item in results.brainstormItems {
                let content = item.editedBody
                let idea = BrainstormIdea(
                    content: content,
                    colorHex: BrainstormIdea.randomColor(),
                    isVoiceNote: false
                )
                modelContext.insert(idea)
            }
            
            // Save and wait for CloudKit activity to complete
            try modelContext.save()
            
            // Small delay to allow CloudKit activity to transition to DONE state
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            savedCount = results.approvedJokes.count
            brainstormCount = results.brainstormItems.count
            showingSaveConfirmation = true
            
            print("✅ [ImportReview] Successfully saved \(savedCount) joke(s) and \(brainstormCount) brainstorm idea(s)")
        } catch {
            print("❌ [ImportReview] Failed to save: \(error.localizedDescription)")
            // Show error to user but don't dismiss
            let nsError = error as NSError
            print("   Domain: \(nsError.domain), Code: \(nsError.code)")
            if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                print("   Underlying: \(underlyingError.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SmartImportReviewView(
        importResult: ImportPipelineResult(
            sourceFile: "test.txt",
            autoSavedJokes: [],
            reviewQueueJokes: [],
            rejectedBlocks: [],
            pipelineStats: PipelineStats(
                totalPagesProcessed: 1, totalLinesExtracted: 10,
                totalBlocksCreated: 3, autoSavedCount: 2,
                reviewQueueCount: 1, rejectedCount: 0,
                extractionMethod: .documentText,
                processingTimeSeconds: 0.5, averageConfidence: 0.7
            ),
            debugInfo: nil
        )
    )
}
