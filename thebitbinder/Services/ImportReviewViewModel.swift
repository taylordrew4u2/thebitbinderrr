//
//  ImportReviewViewModel.swift
//  thebitbinder
//
//  Review interface for low-confidence imports
//

import Foundation
import SwiftUI

/// ViewModel for managing import review flow — joke-by-joke
@MainActor
final class ImportReviewViewModel: ObservableObject {
    
    @Published var reviewItems: [ImportReviewItem] = []
    @Published var currentIndex = 0
    @Published var isProcessing = false
    /// Set when extraction hits a rate-limit or all providers fail during import.
    @Published var rateLimitError: AIExtractionFailedError? = nil

    // Gemini request stats (quota tracking - TODO: implement)
    var geminiRequestsRemaining: Int { Int.max }
    var geminiRequestsUsed: Int      { 0 }

    /// Indices of items that were auto-accepted (from the high-confidence autoSavedJokes bucket)
    private(set) var autoAcceptedIndices: Set<Int> = []
    
    private let pipelineCoordinator = ImportPipelineCoordinator.shared
    
    var currentItem: ImportReviewItem? {
        guard currentIndex < reviewItems.count else { return nil }
        return reviewItems[currentIndex]
    }
    
    var hasNext: Bool {
        currentIndex < reviewItems.count - 1
    }
    
    var hasPrevious: Bool {
        currentIndex > 0
    }
    
    var progressText: String {
        guard !reviewItems.isEmpty else { return "" }
        return "\(currentIndex + 1) of \(reviewItems.count)"
    }
    
    // MARK: - Initialization
    
    /// Load ALL jokes (auto-saved + review queue) so the user sees everything
    func loadAllItems(from result: ImportPipelineResult) {
        let autoSaved = result.autoSavedJokes
        let review = result.reviewQueueJokes
        let allJokes = autoSaved + review
        
        self.reviewItems = allJokes.map { joke in
            ImportReviewItem(
                id: joke.id,
                originalJoke: joke,
                editedTitle: joke.title ?? "",
                editedBody: joke.body,
                editedTags: joke.tags,
                action: .pending,
                splitPoints: [],
                mergeWithNext: false
            )
        }
        
        // Auto-approve the high-confidence items that came from autoSavedJokes
        var indices = Set<Int>()
        for i in 0..<autoSaved.count {
            reviewItems[i].action = .approved
            indices.insert(i)
        }
        autoAcceptedIndices = indices
        
        // Start the current index at the first pending (review queue) item
        self.currentIndex = autoSaved.count < allJokes.count ? autoSaved.count : 0
    }
    
    /// Load only review-queue items (original behavior)
    func loadReviewItems(from result: ImportPipelineResult) {
        self.reviewItems = result.reviewQueueJokes.map { joke in
            ImportReviewItem(
                id: joke.id,
                originalJoke: joke,
                editedTitle: joke.title ?? "",
                editedBody: joke.body,
                editedTags: joke.tags,
                action: .pending,
                splitPoints: [],
                mergeWithNext: false
            )
        }
        self.currentIndex = 0
    }
    
    // MARK: - Navigation
    
    func goToNext() {
        if hasNext {
            currentIndex += 1
        }
    }
    
    func goToPrevious() {
        if hasPrevious {
            currentIndex -= 1
        }
    }
    
    func goToItem(at index: Int) {
        guard index >= 0 && index < reviewItems.count else { return }
        currentIndex = index
    }
    
    // MARK: - Review Actions
    
    /// Tracks the last action for undo support: (item index, previous action)
    @Published var lastAction: (index: Int, previousAction: ReviewAction)? = nil
    
    func approveCurrentItem() {
        guard currentIndex < reviewItems.count else { return }
        let prev = reviewItems[currentIndex].action
        lastAction = (currentIndex, prev)
        reviewItems[currentIndex].action = .approved
        autoAdvance()
    }
    
    func rejectCurrentItem() {
        guard currentIndex < reviewItems.count else { return }
        let prev = reviewItems[currentIndex].action
        lastAction = (currentIndex, prev)
        reviewItems[currentIndex].action = .rejected
        autoAdvance()
    }
    
    func sendCurrentToBrainstorm() {
        guard currentIndex < reviewItems.count else { return }
        let prev = reviewItems[currentIndex].action
        lastAction = (currentIndex, prev)
        reviewItems[currentIndex].action = .sendToBrainstorm
        autoAdvance()
    }
    
    /// Undoes the last review action and navigates back to that item.
    func undoLastAction() {
        guard let (index, previousAction) = lastAction else { return }
        guard index < reviewItems.count else { return }
        reviewItems[index].action = previousAction
        currentIndex = index
        lastAction = nil
    }
    
    /// Whether undo is available
    var canUndo: Bool { lastAction != nil }
    
    func markForSplitting() {
        guard currentIndex < reviewItems.count else { return }
        reviewItems[currentIndex].action = .needsSplitting
    }
    
    func updateCurrentItemText(title: String, body: String, tags: [String]) {
        guard currentIndex < reviewItems.count else { return }
        reviewItems[currentIndex].editedTitle = title
        reviewItems[currentIndex].editedBody = body
        reviewItems[currentIndex].editedTags = tags
    }
    
    private func autoAdvance() {
        if hasNext {
            currentIndex += 1
        }
    }
    
    // MARK: - Batch Operations
    
    func approveAll() {
        for i in 0..<reviewItems.count where reviewItems[i].action == .pending {
            reviewItems[i].action = .approved
        }
    }
    
    func rejectAll() {
        for i in 0..<reviewItems.count where reviewItems[i].action == .pending {
            reviewItems[i].action = .rejected
        }
    }
    
    // MARK: - Processing Results
    
    func getReviewResults() -> ImportReviewResults {
        let approved = reviewItems.compactMap { item in
            item.action == .approved ? item.createFinalJoke() : nil
        }
        
        let rejected = reviewItems.compactMap { item in
            item.action == .rejected ? item.originalJoke : nil
        }
        
        let needsSplitting = reviewItems.compactMap { item in
            item.action == .needsSplitting ? item.originalJoke : nil
        }
        
        let pending = reviewItems.compactMap { item in
            item.action == .pending ? item.originalJoke : nil
        }
        
        let brainstorm = reviewItems.compactMap { item in
            item.action == .sendToBrainstorm ? item : nil
        }
        
        return ImportReviewResults(
            approvedJokes: approved,
            rejectedJokes: rejected,
            jokesNeedingSplitting: needsSplitting,
            pendingJokes: pending,
            brainstormItems: brainstorm
        )
    }
    
    // MARK: - Computed Counts
    
    /// Number of items that were auto-accepted (high confidence, pre-approved)
    var autoAcceptedCount: Int {
        autoAcceptedIndices.count
    }
    
    /// Number of items still pending review
    var pendingCount: Int {
        reviewItems.filter { $0.action == .pending }.count
    }
    
    /// GagGrabber daily budget status (quota tracking – unlimited for now)
    var gagGrabberStatus: GagGrabberBudgetStatus {
        GagGrabberBudgetStatus(
            shortStatusText: "Unlimited",
            statusIcon: "infinity",
            statusColor: .green
        )
    }
    
    var allItemsReviewed: Bool {
        return reviewItems.allSatisfy { $0.action != .pending }
    }
    
    var summaryText: String {
        let approved = reviewItems.filter { $0.action == .approved }.count
        let rejected = reviewItems.filter { $0.action == .rejected }.count
        let brainstorm = reviewItems.filter { $0.action == .sendToBrainstorm }.count
        let pending = reviewItems.filter { $0.action == .pending }.count
        
        var parts: [String] = []
        if approved > 0 { parts.append("✅ \(approved)") }
        if rejected > 0 { parts.append("❌ \(rejected)") }
        if brainstorm > 0 { parts.append("💡 \(brainstorm)") }
        if pending > 0 { parts.append("⏳ \(pending)") }
        return parts.joined(separator: "  ")
    }
}

// MARK: - Supporting Types

struct ImportReviewItem: Identifiable {
    let id: UUID
    let originalJoke: ImportedJoke
    var editedTitle: String
    var editedBody: String
    var editedTags: [String]
    var action: ReviewAction
    var splitPoints: [Int]
    var mergeWithNext: Bool
    
    var hasBeenEdited: Bool {
        return editedTitle != (originalJoke.title ?? "") ||
               editedBody != originalJoke.body ||
               editedTags != originalJoke.tags
    }
    
    var isComplete: Bool {
        return action != .pending
    }
    
    func createFinalJoke() -> ImportedJoke {
        let finalTitle: String? = {
            if !editedTitle.isEmpty { return editedTitle }
            let generated = KeywordTitleGenerator.title(from: editedBody)
            return generated.isEmpty ? nil : generated
        }()
        
        return ImportedJoke(
            title: finalTitle,
            body: editedBody,
            rawSourceText: originalJoke.rawSourceText,
            tags: editedTags,
            confidence: .medium,
            confidenceFactors: ConfidenceFactors(
                extractionQuality: originalJoke.confidenceFactors.extractionQuality,
                structuralCleanliness: 0.8,
                titleDetection: editedTitle.isEmpty ? 0.5 : 0.9,
                boundaryClarity: originalJoke.confidenceFactors.boundaryClarity,
                ocrConfidence: originalJoke.confidenceFactors.ocrConfidence
            ),
            sourceMetadata: originalJoke.sourceMetadata,
            validationResult: .singleJoke,
            extractionMethod: originalJoke.extractionMethod
        )
    }
}

enum ReviewAction {
    case pending
    case approved
    case rejected
    case needsSplitting
    case sendToBrainstorm
}

struct ImportReviewResults {
    let approvedJokes: [ImportedJoke]
    let rejectedJokes: [ImportedJoke]
    let jokesNeedingSplitting: [ImportedJoke]
    let pendingJokes: [ImportedJoke]
    let brainstormItems: [ImportReviewItem]
    
    var totalCount: Int {
        approvedJokes.count + rejectedJokes.count + jokesNeedingSplitting.count + pendingJokes.count + brainstormItems.count
    }
    
    var isComplete: Bool {
        pendingJokes.isEmpty
    }
    
    /// Status of the GagGrabber daily budget for extracted jokes
    var gagGrabberStatus: GagGrabberBudgetStatus {
        // For now, return "Unlimited" - quotas can be added later
        GagGrabberBudgetStatus(
            shortStatusText: "Unlimited",
            statusIcon: "infinity",
            statusColor: .green
        )
    }

}


// MARK: - Budget Status

struct GagGrabberBudgetStatus {
    let shortStatusText: String
    let statusIcon: String
    let statusColor: Color
}
