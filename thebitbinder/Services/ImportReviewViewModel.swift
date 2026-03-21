//
//  ImportReviewViewModel.swift
//  thebitbinder
//
//  Review interface for low-confidence imports
//

import Foundation
import SwiftUI

/// ViewModel for managing import review flow
@MainActor
final class ImportReviewViewModel: ObservableObject {
    
    @Published var reviewItems: [ImportReviewItem] = []
    @Published var currentIndex = 0
    @Published var isProcessing = false
    
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
    
    func loadReviewItems(from result: ImportPipelineResult) {
        self.reviewItems = result.reviewQueueJokes.map { joke in
            ImportReviewItem(
                id: joke.id,
                originalJoke: joke,
                editedTitle: joke.title ?? "",
                editedBody: joke.body,
                editedTags: joke.tags,
                action: .pending,
                splitPoints: [], // Could be populated if we support splitting in review
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
        guard let item = currentItem else { return }
        
        // Update the item with user edits
        reviewItems[currentIndex] = ImportReviewItem(
            id: item.id,
            originalJoke: item.originalJoke,
            editedTitle: item.editedTitle,
            editedBody: item.editedBody,
            editedTags: item.editedTags,
            action: .approved,
            splitPoints: item.splitPoints,
            mergeWithNext: item.mergeWithNext
        )
        
        // Auto-advance to next item
        if hasNext {
            goToNext()
        }
    }
    
    func rejectCurrentItem() {
        guard let item = currentItem else { return }
        
        reviewItems[currentIndex] = ImportReviewItem(
            id: item.id,
            originalJoke: item.originalJoke,
            editedTitle: item.editedTitle,
            editedBody: item.editedBody,
            editedTags: item.editedTags,
            action: .rejected,
            splitPoints: item.splitPoints,
            mergeWithNext: item.mergeWithNext
        )
        
        // Auto-advance to next item
        if hasNext {
            goToNext()
        }
    }
    
    func markForSplitting() {
        guard let item = currentItem else { return }
        
        reviewItems[currentIndex] = ImportReviewItem(
            id: item.id,
            originalJoke: item.originalJoke,
            editedTitle: item.editedTitle,
            editedBody: item.editedBody,
            editedTags: item.editedTags,
            action: .needsSplitting,
            splitPoints: item.splitPoints,
            mergeWithNext: item.mergeWithNext
        )
    }
    
    func updateCurrentItemText(title: String, body: String, tags: [String]) {
        guard let item = currentItem else { return }
        
        reviewItems[currentIndex] = ImportReviewItem(
            id: item.id,
            originalJoke: item.originalJoke,
            editedTitle: title,
            editedBody: body,
            editedTags: tags,
            action: item.action,
            splitPoints: item.splitPoints,
            mergeWithNext: item.mergeWithNext
        )
    }
    
    // MARK: - Batch Operations
    
    func approveAll() {
        for i in 0..<reviewItems.count {
            let item = reviewItems[i]
            reviewItems[i] = ImportReviewItem(
                id: item.id,
                originalJoke: item.originalJoke,
                editedTitle: item.editedTitle,
                editedBody: item.editedBody,
                editedTags: item.editedTags,
                action: .approved,
                splitPoints: item.splitPoints,
                mergeWithNext: item.mergeWithNext
            )
        }
    }
    
    func rejectAll() {
        for i in 0..<reviewItems.count {
            let item = reviewItems[i]
            reviewItems[i] = ImportReviewItem(
                id: item.id,
                originalJoke: item.originalJoke,
                editedTitle: item.editedTitle,
                editedBody: item.editedBody,
                editedTags: item.editedTags,
                action: .rejected,
                splitPoints: item.splitPoints,
                mergeWithNext: item.mergeWithNext
            )
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
        
        return ImportReviewResults(
            approvedJokes: approved,
            rejectedJokes: rejected,
            jokesNeedingSplitting: needsSplitting,
            pendingJokes: pending
        )
    }
    
    var allItemsReviewed: Bool {
        return reviewItems.allSatisfy { $0.action != .pending }
    }
    
    var summaryText: String {
        let approved = reviewItems.filter { $0.action == .approved }.count
        let rejected = reviewItems.filter { $0.action == .rejected }.count
        let splitting = reviewItems.filter { $0.action == .needsSplitting }.count
        let pending = reviewItems.filter { $0.action == .pending }.count
        
        return "Approved: \(approved), Rejected: \(rejected), Splitting: \(splitting), Pending: \(pending)"
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
            confidence: .medium, // User review brings confidence to medium
            confidenceFactors: ConfidenceFactors(
                extractionQuality: originalJoke.confidenceFactors.extractionQuality,
                structuralCleanliness: 0.8, // Improved by user review
                titleDetection: editedTitle.isEmpty ? 0.3 : 0.9,
                boundaryClarity: originalJoke.confidenceFactors.boundaryClarity,
                ocrConfidence: originalJoke.confidenceFactors.ocrConfidence
            ),
            sourceMetadata: originalJoke.sourceMetadata,
            validationResult: .singleJoke, // Validated by user
            extractionMethod: originalJoke.extractionMethod
        )
    }
}

enum ReviewAction {
    case pending
    case approved
    case rejected
    case needsSplitting
}

struct ImportReviewResults {
    let approvedJokes: [ImportedJoke]
    let rejectedJokes: [ImportedJoke]
    let jokesNeedingSplitting: [ImportedJoke]
    let pendingJokes: [ImportedJoke]
    
    var totalCount: Int {
        approvedJokes.count + rejectedJokes.count + jokesNeedingSplitting.count + pendingJokes.count
    }
    
    var isComplete: Bool {
        pendingJokes.isEmpty
    }
}
