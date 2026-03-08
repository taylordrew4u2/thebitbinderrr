//
//  CategorizationResult.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/8/25.
//

import Foundation

// MARK: - Category Matching Result
struct CategoryMatch: Codable {
    var category: String
    var confidence: Double  // 0.0 to 1.0
    var reasoning: String
    var matchedKeywords: [String]
    
    // Metadata fields used by AutoOrganizeService
    var styleTags: [String]
    var emotionalTone: String?
    var craftSignals: [String]
    var structureScore: Double?
    
    var confidencePercent: String {
        String(format: "%.0f%%", confidence * 100)
    }
}

