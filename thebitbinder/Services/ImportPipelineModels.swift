//
//  ImportPipelineModels.swift
//  thebitbinder
//
//  Created for the new import pipeline architecture
//

import Foundation
import CoreGraphics

// MARK: - File Type Detection

enum ImportFileType {
    case textPDF
    case scannedPDF
    case image
    case document
    case unknown
}

enum ExtractionMethod: String, Codable {
    case pdfKitText = "PDFKit Text"
    case visionOCR = "Vision OCR"
    case documentText = "Document Text"
    case imageOCR = "Image OCR"
}

// MARK: - Line-Level Models

struct ExtractedLine: Identifiable {
    let id = UUID()
    let rawText: String
    let normalizedText: String
    let pageNumber: Int
    let lineNumber: Int
    let boundingBox: CGRect
    let confidence: Float
    let estimatedFontSize: Float?
    let indentationLevel: Int
    let yPosition: Float
    let method: ExtractionMethod
}

struct NormalizedPage {
    let pageNumber: Int
    let lines: [ExtractedLine]
    let hasRepeatingHeader: Bool
    let hasRepeatingFooter: Bool
    let averageLineHeight: Float
    let pageHeight: Float
}

// MARK: - Layout-Based Blocks

enum BlockSeparationType {
    case largeVerticalGap    // Strong separator
    case indentationChange   // Medium separator  
    case titleDetected       // Strong separator
    case bulletOrNumber      // Strong separator
    case pageBreak          // Medium separator
    case structuralChange   // Medium separator
}

struct LayoutBlock: Identifiable {
    let id = UUID()
    let lines: [ExtractedLine]
    let blockType: BlockType
    let separatorBefore: BlockSeparationType?
    let separatorAfter: BlockSeparationType?
    let averageLineSpacing: Float
    let totalHeight: Float
    let indentationPattern: [Int]
    let containsTitle: Bool
    let pageNumber: Int
    let orderInPage: Int
    
    var text: String {
        lines.map(\.normalizedText).joined(separator: "\n")
    }
    
    var rawText: String {
        lines.map(\.rawText).joined(separator: "\n")
    }
}

enum BlockType {
    case singleJoke
    case suspectedMultipleJokes
    case title
    case note
    case metadata
    case unknown
}

// MARK: - Validation Results

enum ValidationResult {
    case singleJoke
    case multipleJokes(suspectedCount: Int, reasons: [String])
    case requiresReview(reasons: [String])
    case notAJoke(reason: String)
}

struct BlockValidation {
    let block: LayoutBlock
    let result: ValidationResult
    let confidence: ImportConfidence
    let issues: [ValidationIssue]
    
    var shouldAutoSave: Bool {
        switch result {
        case .singleJoke:
            return confidence == .high
        default:
            return false
        }
    }
    
    var requiresReview: Bool {
        switch result {
        case .singleJoke:
            return confidence == .low
        case .multipleJokes, .requiresReview:
            return true
        case .notAJoke:
            return false
        }
    }
}

struct ValidationIssue {
    let type: IssueType
    let description: String
    let severity: IssueSeverity
    
    enum IssueType {
        case multipleTitles
        case multipleBlankGaps
        case repeatedNumbering
        case unusualLength
        case topicShift
        case structuralAmbiguity
        case lowOCRConfidence
    }
    
    enum IssueSeverity {
        case low, medium, high
    }
}

// MARK: - Confidence Scoring

enum ImportConfidence: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium" 
    case low = "low"
    
    var threshold: Float {
        switch self {
        case .high: return 0.8
        case .medium: return 0.6
        case .low: return 0.0
        }
    }
}

struct ConfidenceFactors {
    let extractionQuality: Float        // 0.0-1.0
    let structuralCleanliness: Float    // 0.0-1.0
    let titleDetection: Float           // 0.0-1.0
    let boundaryClarity: Float          // 0.0-1.0
    let ocrConfidence: Float            // 0.0-1.0
    
    var overallScore: Float {
        (extractionQuality + structuralCleanliness + titleDetection + boundaryClarity + ocrConfidence) / 5.0
    }
    
    var importConfidence: ImportConfidence {
        if overallScore >= ImportConfidence.high.threshold {
            return .high
        } else if overallScore >= ImportConfidence.medium.threshold {
            return .medium
        } else {
            return .low
        }
    }
}

// MARK: - Final Joke Objects

struct ImportedJoke {
    let id = UUID()
    let title: String?
    let body: String
    let rawSourceText: String
    let tags: [String]
    let confidence: ImportConfidence
    let confidenceFactors: ConfidenceFactors
    let sourceMetadata: ImportSourceMetadata
    let validationResult: ValidationResult
    let extractionMethod: ExtractionMethod
    
    var needsReview: Bool {
        switch validationResult {
        case .singleJoke:
            return confidence == .low
        case .multipleJokes, .requiresReview:
            return true
        case .notAJoke:
            return false
        }
    }
}

struct ImportSourceMetadata {
    let fileName: String
    let pageNumber: Int
    let orderInPage: Int
    let orderInFile: Int
    let boundingBox: CGRect?
    let importTimestamp: Date
    let pipelineVersion: String = "2.0"
}

// MARK: - Pipeline Result

struct ImportPipelineResult {
    let sourceFile: String
    let autoSavedJokes: [ImportedJoke]          // High confidence, validated single jokes
    let reviewQueueJokes: [ImportedJoke]        // Needs user review
    let rejectedBlocks: [LayoutBlock]           // Not jokes, don't save
    let pipelineStats: PipelineStats
    let debugInfo: PipelineDebugInfo?
}

struct PipelineStats {
    let totalPagesProcessed: Int
    let totalLinesExtracted: Int
    let totalBlocksCreated: Int
    let autoSavedCount: Int
    let reviewQueueCount: Int
    let rejectedCount: Int
    let extractionMethod: ExtractionMethod
    let processingTimeSeconds: Double
    let averageConfidence: Float
}

struct PipelineDebugInfo {
    let fileTypeDetection: String
    let extractionDetails: String
    let blockSplittingDecisions: [String]
    let validationDecisions: [String]
    let confidenceCalculations: [String]
}

// MARK: - Custom Words for OCR

struct OCRCustomWords {
    let jokeTitle: [String]
    let venueName: [String]
    let comedyTerms: [String]
    let userSlang: [String]
    
    var allWords: [String] {
        jokeTitle + venueName + comedyTerms + userSlang
    }
    
    static let defaultComedyTerms = [
        "heckler", "callback", "punchline", "setup", "premise", "tag",
        "improv", "standup", "mic", "stage", "crowd", "audience",
        "applause", "laugh", "chuckle", "groan", "bombing", "killing"
    ]
}
