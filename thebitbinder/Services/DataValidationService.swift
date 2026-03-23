//
//  DataValidationService.swift
//  thebitbinder
//
//  Created for data integrity validation and corruption detection
//

import Foundation
import SwiftData

/// Service to validate data integrity and detect potential corruption or data loss
@MainActor
final class DataValidationService: ObservableObject {
    
    static let shared = DataValidationService()
    
    // Track data counts for validation
    private let countsKey = "DataValidation_Counts"
    
    init() {
        print("🔍 [DataValidation] Service initialized")
    }
    
    // MARK: - Data Integrity Checks
    
    /// Performs comprehensive data validation
    func validateDataIntegrity(context: ModelContext) async -> DataValidationResult {
        var result = DataValidationResult()
        
        print("🔍 [DataValidation] Starting data integrity check...")
        
        // Count all entities
        result.jokesCount = await countEntities(of: Joke.self, context: context)
        result.foldersCount = await countEntities(of: JokeFolder.self, context: context)
        result.recordingsCount = await countEntities(of: Recording.self, context: context)
        result.setListsCount = await countEntities(of: SetList.self, context: context)
        result.roastTargetsCount = await countEntities(of: RoastTarget.self, context: context)
        result.roastJokesCount = await countEntities(of: RoastJoke.self, context: context)
        result.brainstormIdeasCount = await countEntities(of: BrainstormIdea.self, context: context)
        result.notebookPhotoRecordsCount = await countEntities(of: NotebookPhotoRecord.self, context: context)
        result.importBatchesCount = await countEntities(of: ImportBatch.self, context: context)
        result.chatMessagesCount = await countEntities(of: ChatMessage.self, context: context)
        
        // Check for data corruption patterns
        await validateJokes(context: context, result: &result)
        await validateRecordings(context: context, result: &result)
        await validateRelationships(context: context, result: &result)
        
        // Compare with previous counts
        let previousCounts = getPreviousCounts()
        result.previousCounts = previousCounts
        result.significantDataLoss = detectSignificantDataLoss(current: result, previous: previousCounts)
        
        // Save current counts for next validation
        saveCurrentCounts(result)
        
        result.validationDate = Date()
        
        print("🔍 [DataValidation] Validation completed")
        print("🔍 [DataValidation] Total entities: \(result.totalEntities)")
        
        if !result.issues.isEmpty {
            print("⚠️ [DataValidation] Found \(result.issues.count) issues")
            for issue in result.issues {
                print("   - \(issue)")
            }
        }
        
        if result.significantDataLoss {
            print("🚨 [DataValidation] SIGNIFICANT DATA LOSS DETECTED!")
        }
        
        return result
    }
    
    private func countEntities<T: PersistentModel>(of type: T.Type, context: ModelContext) async -> Int {
        do {
            let descriptor = FetchDescriptor<T>()
            let entities = try context.fetch(descriptor)
            return entities.count
        } catch {
            print("❌ [DataValidation] Failed to count \(type): \(error)")
            return 0
        }
    }
    
    // MARK: - Entity-Specific Validation
    
    private func validateJokes(context: ModelContext, result: inout DataValidationResult) async {
        do {
            let jokes = try context.fetch(FetchDescriptor<Joke>())
            
            var emptyJokes = 0
            var jokesWithoutDates = 0
            var orphanedJokes = 0
            
            for joke in jokes {
                // Check for empty content
                if joke.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyJokes += 1
                }
                
                // Check for missing dates (corruption indicator)
                if joke.dateCreated < Date(timeIntervalSince1970: 0) {
                    jokesWithoutDates += 1
                }
                
                // Check for relationship integrity
                if let folder = joke.folder {
                    // Verify folder still exists and is accessible
                    if folder.name.isEmpty && folder.dateCreated < Date(timeIntervalSince1970: 0) {
                        orphanedJokes += 1
                    }
                }
            }
            
            if emptyJokes > 0 {
                result.issues.append("Found \(emptyJokes) jokes with empty content")
            }
            
            if jokesWithoutDates > 0 {
                result.issues.append("Found \(jokesWithoutDates) jokes with invalid dates (possible corruption)")
            }
            
            if orphanedJokes > 0 {
                result.issues.append("Found \(orphanedJokes) jokes with invalid folder references")
            }
            
        } catch {
            result.issues.append("Failed to validate jokes: \(error.localizedDescription)")
        }
    }
    
    private func validateRecordings(context: ModelContext, result: inout DataValidationResult) async {
        do {
            let recordings = try context.fetch(FetchDescriptor<Recording>())
            
            var invalidFileURLs = 0
            var missingFiles = 0
            
            for recording in recordings {
                // Check if file URL is valid
                if recording.fileURL.isEmpty {
                    invalidFileURLs += 1
                    continue
                }
                
                // Check if file actually exists
                let fileURL = URL(fileURLWithPath: recording.fileURL)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    missingFiles += 1
                }
            }
            
            if invalidFileURLs > 0 {
                result.issues.append("Found \(invalidFileURLs) recordings with invalid file URLs")
            }
            
            if missingFiles > 0 {
                result.issues.append("Found \(missingFiles) recordings with missing files")
            }
            
        } catch {
            result.issues.append("Failed to validate recordings: \(error.localizedDescription)")
        }
    }
    
    private func validateRelationships(context: ModelContext, result: inout DataValidationResult) async {
        do {
            // Check joke-folder relationships
            let jokes = try context.fetch(FetchDescriptor<Joke>())
            let folders = try context.fetch(FetchDescriptor<JokeFolder>())
            
            var brokenFolderRelationships = 0
            
            for joke in jokes {
                if let folder = joke.folder {
                    // Check if the folder actually exists in the database
                    if !folders.contains(where: { $0.id == folder.id }) {
                        brokenFolderRelationships += 1
                    }
                }
            }
            
            if brokenFolderRelationships > 0 {
                result.issues.append("Found \(brokenFolderRelationships) broken joke-folder relationships")
            }
            
            // Check roast target relationships
            let roastJokes = try context.fetch(FetchDescriptor<RoastJoke>())
            let roastTargets = try context.fetch(FetchDescriptor<RoastTarget>())
            
            var brokenRoastRelationships = 0
            
            for roastJoke in roastJokes {
                if let target = roastJoke.target {
                    if !roastTargets.contains(where: { $0.id == target.id }) {
                        brokenRoastRelationships += 1
                    }
                }
            }
            
            if brokenRoastRelationships > 0 {
                result.issues.append("Found \(brokenRoastRelationships) broken roast joke-target relationships")
            }
            
        } catch {
            result.issues.append("Failed to validate relationships: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Loss Detection
    
    private func detectSignificantDataLoss(current: DataValidationResult, previous: DataValidationCounts?) -> Bool {
        guard let previous = previous else { return false }
        
        let thresholdPercentage: Double = 0.1 // 10% loss is considered significant
        
        // Check each entity type for significant loss
        let losses = [
            (current.jokesCount, previous.jokesCount),
            (current.foldersCount, previous.foldersCount),
            (current.recordingsCount, previous.recordingsCount),
            (current.setListsCount, previous.setListsCount),
            (current.roastTargetsCount, previous.roastTargetsCount),
            (current.roastJokesCount, previous.roastJokesCount),
            (current.brainstormIdeasCount, previous.brainstormIdeasCount),
            (current.notebookPhotoRecordsCount, previous.notebookPhotoRecordsCount)
        ]
        
        for (current, previous) in losses {
            if previous > 0 {
                let lossPercentage = Double(previous - current) / Double(previous)
                if lossPercentage > thresholdPercentage {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Persistence
    
    private func getPreviousCounts() -> DataValidationCounts? {
        guard let data = UserDefaults.standard.data(forKey: countsKey),
              let counts = try? JSONDecoder().decode(DataValidationCounts.self, from: data) else {
            return nil
        }
        return counts
    }
    
    private func saveCurrentCounts(_ result: DataValidationResult) {
        let counts = DataValidationCounts(
            jokesCount: result.jokesCount,
            foldersCount: result.foldersCount,
            recordingsCount: result.recordingsCount,
            setListsCount: result.setListsCount,
            roastTargetsCount: result.roastTargetsCount,
            roastJokesCount: result.roastJokesCount,
            brainstormIdeasCount: result.brainstormIdeasCount,
            notebookPhotoRecordsCount: result.notebookPhotoRecordsCount,
            importBatchesCount: result.importBatchesCount,
            chatMessagesCount: result.chatMessagesCount,
            validationDate: Date()
        )
        
        if let data = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(data, forKey: countsKey)
        }
    }
    
    // MARK: - Repair Functions
    
    /// Attempts to repair common data issues
    func repairDataIssues(context: ModelContext, issues: [String]) async -> [String] {
        var repairedIssues: [String] = []
        
        for issue in issues {
            if issue.contains("empty content") {
                // Could implement repair for empty jokes
            } else if issue.contains("invalid dates") {
                if await repairInvalidDates(context: context) {
                    repairedIssues.append(issue)
                }
            } else if issue.contains("broken") && issue.contains("relationships") {
                if await repairBrokenRelationships(context: context) {
                    repairedIssues.append(issue)
                }
            }
        }
        
        return repairedIssues
    }
    
    private func repairInvalidDates(context: ModelContext) async -> Bool {
        do {
            let jokes = try context.fetch(FetchDescriptor<Joke>())
            var repairedCount = 0
            
            for joke in jokes {
                if joke.dateCreated < Date(timeIntervalSince1970: 0) {
                    joke.dateCreated = Date()
                    joke.dateModified = Date()
                    repairedCount += 1
                }
            }
            
            if repairedCount > 0 {
                try context.save()
                print("✅ [DataValidation] Repaired \(repairedCount) jokes with invalid dates")
            }
            
            return repairedCount > 0
        } catch {
            print("❌ [DataValidation] Failed to repair invalid dates: \(error)")
            return false
        }
    }
    
    private func repairBrokenRelationships(context: ModelContext) async -> Bool {
        do {
            let jokes = try context.fetch(FetchDescriptor<Joke>())
            let folders = try context.fetch(FetchDescriptor<JokeFolder>())
            
            var repairedCount = 0
            
            for joke in jokes {
                if let folder = joke.folder {
                    // If folder doesn't exist in database, remove the relationship
                    if !folders.contains(where: { $0.id == folder.id }) {
                        joke.folder = nil
                        repairedCount += 1
                    }
                }
            }
            
            if repairedCount > 0 {
                try context.save()
                print("✅ [DataValidation] Repaired \(repairedCount) broken folder relationships")
            }
            
            // Repair RoastJoke → RoastTarget relationships
            let roastJokes = try context.fetch(FetchDescriptor<RoastJoke>())
            let roastTargets = try context.fetch(FetchDescriptor<RoastTarget>())
            
            var roastRepaired = 0
            var orphanedRoastJokes: [RoastJoke] = []
            
            for roastJoke in roastJokes {
                if let target = roastJoke.target {
                    // Check if the target still exists
                    if !roastTargets.contains(where: { $0.id == target.id }) {
                        // Target reference is broken — null it out so it doesn't crash
                        roastJoke.target = nil
                        orphanedRoastJokes.append(roastJoke)
                        roastRepaired += 1
                    }
                } else {
                    // Roast joke has no target at all — it's an orphan
                    orphanedRoastJokes.append(roastJoke)
                }
            }
            
            // Try to re-home orphaned roast jokes to a target if there's exactly one,
            // or to the most recently modified target as a recovery bucket
            if !orphanedRoastJokes.isEmpty && !roastTargets.isEmpty {
                // Sort targets by most recent modification
                let sortedTargets = roastTargets.sorted { $0.dateModified > $1.dateModified }
                
                if roastTargets.count == 1 {
                    // Only one target — clearly they all belong there
                    let onlyTarget = roastTargets[0]
                    for roastJoke in orphanedRoastJokes {
                        roastJoke.target = onlyTarget
                        roastRepaired += 1
                    }
                    print("✅ [DataValidation] Re-assigned \(orphanedRoastJokes.count) orphaned roast jokes to '\(onlyTarget.name)'")
                } else {
                    // Multiple targets — assign to most recently modified as recovery
                    // User can manually move them later
                    let recoveryTarget = sortedTargets[0]
                    for roastJoke in orphanedRoastJokes where roastJoke.target == nil {
                        roastJoke.target = recoveryTarget
                        roastRepaired += 1
                    }
                    print("⚠️ [DataValidation] Re-assigned \(orphanedRoastJokes.count) orphaned roast jokes to '\(recoveryTarget.name)' for recovery — user should verify")
                }
            }
            
            if roastRepaired > 0 {
                try context.save()
                print("✅ [DataValidation] Repaired \(roastRepaired) broken roast relationships")
            }
            
            return (repairedCount + roastRepaired) > 0
        } catch {
            print("❌ [DataValidation] Failed to repair relationships: \(error)")
            return false
        }
    }
}

// MARK: - Supporting Types

struct DataValidationResult {
    var validationDate = Date()
    var jokesCount = 0
    var foldersCount = 0
    var recordingsCount = 0
    var setListsCount = 0
    var roastTargetsCount = 0
    var roastJokesCount = 0
    var brainstormIdeasCount = 0
    var notebookPhotoRecordsCount = 0
    var importBatchesCount = 0
    var chatMessagesCount = 0
    
    var totalEntities: Int {
        jokesCount + foldersCount + recordingsCount + setListsCount +
        roastTargetsCount + roastJokesCount + brainstormIdeasCount +
        notebookPhotoRecordsCount + importBatchesCount + chatMessagesCount
    }
    
    var issues: [String] = []
    var previousCounts: DataValidationCounts?
    var significantDataLoss = false
    
    var isHealthy: Bool {
        issues.isEmpty && !significantDataLoss
    }
}

struct DataValidationCounts: Codable {
    let jokesCount: Int
    let foldersCount: Int
    let recordingsCount: Int
    let setListsCount: Int
    let roastTargetsCount: Int
    let roastJokesCount: Int
    let brainstormIdeasCount: Int
    let notebookPhotoRecordsCount: Int
    let importBatchesCount: Int
    let chatMessagesCount: Int
    let validationDate: Date
}
