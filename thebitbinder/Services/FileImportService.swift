import Foundation
import UIKit
import SwiftData

final class FileImportService {
    static let shared = FileImportService()
    
    private let pipelineCoordinator = ImportPipelineCoordinator.shared
    private let dataLogger = DataOperationLogger.shared
    
    private init() {}
    
    func importBatch(from url: URL) async throws -> ImportBatchResult {
        dataLogger.logInfo("Starting new pipeline import for \(url.lastPathComponent)")
        
        do {
            let pipelineResult = try await pipelineCoordinator.processFile(url: url)
            
            // Convert pipeline result to legacy format for compatibility
            let legacyResult = convertToLegacyFormat(pipelineResult)
            
            dataLogger.logInfo("Pipeline import completed: \(pipelineResult.autoSavedJokes.count) auto-saved, \(pipelineResult.reviewQueueJokes.count) need review")
            
            return legacyResult
            
        } catch {
            dataLogger.logError(error, operation: "PIPELINE_IMPORT", context: url.lastPathComponent)
            throw error
        }
    }
    
    /// Modern import method that returns the full pipeline result
    func importWithPipeline(from url: URL) async throws -> ImportPipelineResult {
        dataLogger.logInfo("Starting pipeline import for \(url.lastPathComponent)")
        
        do {
            let result = try await pipelineCoordinator.processFile(url: url)
            
            dataLogger.logInfo("Pipeline import completed successfully")
            dataLogger.logInfo("Auto-saved: \(result.autoSavedJokes.count)")
            dataLogger.logInfo("Review queue: \(result.reviewQueueJokes.count)")
            dataLogger.logInfo("Rejected: \(result.rejectedBlocks.count)")
            
            return result
            
        } catch {
            dataLogger.logError(error, operation: "PIPELINE_IMPORT", context: url.lastPathComponent)
            throw error
        }
    }
    
    /// Saves approved jokes to the data store
    func saveApprovedJokes(_ jokes: [ImportedJoke], to modelContext: ModelContext) throws {
        for importedJoke in jokes {
            let joke = Joke(content: importedJoke.body, title: importedJoke.title ?? "")
            joke.dateCreated = importedJoke.sourceMetadata.importTimestamp
            joke.dateModified = importedJoke.sourceMetadata.importTimestamp
            
            // Set tags
            joke.tags = importedJoke.tags
            
            modelContext.insert(joke)
            
            dataLogger.logDataCreation(joke, context: modelContext)
        }
        
        try modelContext.save()
        dataLogger.logBulkOperation("IMPORT_SAVE", entityType: "Joke", count: jokes.count, context: modelContext)
    }
    
    // MARK: - Legacy Compatibility
    
    private func convertToLegacyFormat(_ pipelineResult: ImportPipelineResult) -> ImportBatchResult {
        let allJokes = pipelineResult.autoSavedJokes + pipelineResult.reviewQueueJokes
        
        let importedRecords = allJokes.map { joke in
            ImportedJokeRecord(
                id: joke.id,
                title: joke.title ?? "",
                body: joke.body,
                rawSourceText: joke.rawSourceText,
                notes: "",
                tags: joke.tags,
                confidence: convertConfidence(joke.confidence),
                sourceFilename: joke.sourceMetadata.fileName,
                sourceOrder: joke.sourceMetadata.orderInFile,
                importTimestamp: joke.sourceMetadata.importTimestamp,
                parsingFlags: ImportParsingFlags(
                    titleWasInferred: joke.title == nil,
                    containsUnresolvedFragments: joke.confidence == .low,
                    ambiguousBoundaryBefore: false,
                    ambiguousBoundaryAfter: false,
                    originatedFromShortFragment: joke.body.split(whereSeparator: \.isWhitespace).count < 10
                ),
                unresolvedFragments: [],
                sourcePage: joke.sourceMetadata.pageNumber
            )
        }
        
        let unresolvedFragments = pipelineResult.reviewQueueJokes.map { joke in
            ImportedFragment(
                id: UUID(),
                text: joke.rawSourceText,
                normalizedText: joke.body,
                kind: .joke,
                confidence: convertConfidence(joke.confidence),
                sourceLocation: ImportSourceLocation(
                    fileName: joke.sourceMetadata.fileName,
                    pageNumber: joke.sourceMetadata.pageNumber,
                    orderIndex: joke.sourceMetadata.orderInFile
                ),
                tags: joke.tags,
                titleCandidate: joke.title,
                parsingFlags: ImportParsingFlags(
                    titleWasInferred: joke.title == nil,
                    containsUnresolvedFragments: true,
                    ambiguousBoundaryBefore: false,
                    ambiguousBoundaryAfter: false,
                    originatedFromShortFragment: false
                )
            )
        }
        
        return ImportBatchResult(
            sourceFileName: pipelineResult.sourceFile,
            importedRecords: importedRecords,
            unresolvedFragments: unresolvedFragments,
            orderedFragments: unresolvedFragments,
            stats: ImportBatchStats(
                totalSegments: pipelineResult.pipelineStats.totalBlocksCreated,
                totalImportedRecords: pipelineResult.pipelineStats.autoSavedCount + pipelineResult.pipelineStats.reviewQueueCount,
                unresolvedFragmentCount: pipelineResult.pipelineStats.reviewQueueCount,
                highConfidenceBoundaries: pipelineResult.pipelineStats.autoSavedCount,
                mediumConfidenceBoundaries: pipelineResult.pipelineStats.reviewQueueCount,
                lowConfidenceBoundaries: pipelineResult.pipelineStats.rejectedCount
            ),
            importTimestamp: Date()
        )
    }
    
    private func convertConfidence(_ confidence: ImportConfidence) -> ParsingConfidence {
        switch confidence {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}
