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
    /// Set when the Gemini daily rate-limit is hit during import.
    @Published var rateLimitError: GeminiRateLimitError? = nil

    // Gemini request stats (updated on load)
    var geminiRequestsRemaining: Int { GeminiJokeExtractor.shared.remainingRequests() }
    var geminiRequestsUsed: Int      { GeminiJokeExtractor.shared.todayRequestCount() }

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
        let allJokes = result.autoSavedJokes + result.reviewQueueJokes
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
        self.currentIndex = 0
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
    
    func approveCurrentItem() {
        guard currentIndex < reviewItems.count else { return }
        reviewItems[currentIndex].action = .approved
        autoAdvance()
    }
    
    func rejectCurrentItem() {
        guard currentIndex < reviewItems.count else { return }
        reviewItems[currentIndex].action = .rejected
        autoAdvance()
    }
    
    func sendCurrentToBrainstorm() {
        guard currentIndex < reviewItems.count else { return }
        reviewItems[currentIndex].action = .sendToBrainstorm
        autoAdvance()
    }
    
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
        return ImportedJoke(
            title: editedTitle.isEmpty ? nil : editedTitle,
            body: editedBody,
            rawSourceText: originalJoke.rawSourceText,
            tags: editedTags,
            confidence: .medium,
            confidenceFactors: ConfidenceFactors(
                extractionQuality: originalJoke.confidenceFactors.extractionQuality,
                structuralCleanliness: 0.8,
                titleDetection: editedTitle.isEmpty ? 0.3 : 0.9,
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
}
