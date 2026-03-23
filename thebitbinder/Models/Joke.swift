//
//  Joke.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class Joke: Identifiable {
    var id: UUID = UUID()
    var content: String = ""
    var title: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    @Relationship var folder: JokeFolder?
    
    // Soft-delete (trash) support
    var isDeleted: Bool = false
    var deletedDate: Date?
    
    // Smart categorization fields - stored as strings to avoid SwiftData array issues
    @Attribute(.ephemeral) var categorizationResults: [CategoryMatch] = []
    var primaryCategory: String?
    
    // Store as comma-separated string internally
    private var allCategoriesString: String = ""
    private var categoryScoresString: String = ""  // format: "category1:0.8|category2:0.6"
    private var styleTagsString: String = ""  // format: "tag1|tag2"
    private var craftNotesString: String = ""  // format: "signal1|signal2"
    
    // Style metadata
    var comedicTone: String?
    var structureScore: Double = 0.0
    
    // AI categorization
    var category: String?  // Primary category from AI
    private var tagsString: String = ""  // AI-suggested tags stored as comma-separated
    var difficulty: String?  // Easy, Medium, Hard
    var humorRating: Int = 0  // 1-10 rating
    
    // The Hits - perfected jokes that work every time
    var isHit: Bool = false
    
    // Pre-computed word count for fast sorting and filtering
    var wordCount: Int = 0
    
    // Import source tracking
    var importSource: String?  // Source file name if imported
    var importConfidence: String?  // high/medium/low
    var importTimestamp: Date?  // When imported
    
    // Computed property for tags
    var tags: [String] {
        get {
            guard !tagsString.isEmpty else { return [] }
            return tagsString.split(separator: ",").map { String($0) }
        }
        set {
            tagsString = newValue.joined(separator: ",")
        }
    }
    
    // Computed property for allCategories
    var allCategories: [String] {
        get {
            guard !allCategoriesString.isEmpty else { return [] }
            return allCategoriesString.split(separator: ",").map { String($0) }
        }
        set {
            allCategoriesString = newValue.joined(separator: ",")
        }
    }
    
    // Computed property for categoryConfidenceScores
    var categoryConfidenceScores: [String: Double] {
        get {
            guard !categoryScoresString.isEmpty else { return [:] }
            var result: [String: Double] = [:]
            for pair in categoryScoresString.split(separator: "|") {
                let parts = pair.split(separator: ":")
                if parts.count == 2, let score = Double(parts[1]) {
                    result[String(parts[0])] = score
                }
            }
            return result
        }
        set {
            categoryScoresString = newValue.map { "\($0.key):\($0.value)" }.joined(separator: "|")
        }
    }
    
    // Computed property for styleTags
    var styleTags: [String] {
        get {
            guard !styleTagsString.isEmpty else { return [] }
            return styleTagsString.split(separator: "|").map { String($0) }
        }
        set {
            styleTagsString = newValue.joined(separator: "|")
        }
    }
    
    // Computed property for craftNotes
    var craftNotes: [String] {
        get {
            guard !craftNotesString.isEmpty else { return [] }
            return craftNotesString.split(separator: "|").map { String($0) }
        }
        set {
            craftNotesString = newValue.joined(separator: "|")
        }
    }
    
    init(content: String, title: String = "", folder: JokeFolder? = nil) {
        self.id = UUID()
        self.content = content
        self.title = title.isEmpty ? KeywordTitleGenerator.title(from: content) : title
        self.dateCreated = Date()
        self.dateModified = Date()
        self.folder = folder
        self.comedicTone = nil
        self.structureScore = 0.0
        self.wordCount = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        // New jokes start active (not in trash)
        self.isDeleted = false
        self.deletedDate = nil
    }
    
    /// Recalculates and stores the word count. Call after editing `content`.
    func updateWordCount() {
        wordCount = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
    
    // MARK: - Trash Helpers
    
    func moveToTrash() {
        isDeleted = true
        deletedDate = Date()
        dateModified = Date()
    }
    
    func restoreFromTrash() {
        isDeleted = false
        deletedDate = nil
        dateModified = Date()
    }
}
