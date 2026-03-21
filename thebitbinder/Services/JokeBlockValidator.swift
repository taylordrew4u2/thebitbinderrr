//
//  JokeBlockValidator.swift
//  thebitbinder
//
//  Validates that layout blocks contain only single jokes and enforces review requirements
//

import Foundation

/// Validates layout blocks to ensure each contains only one joke
/// This is the critical component that prevents multi-joke merging
final class JokeBlockValidator {
    
    static let shared = JokeBlockValidator()
    private init() {}
    
    /// Validates a block and determines if it should be auto-saved, reviewed, or split further
    func validateBlock(_ block: LayoutBlock) -> BlockValidation {
        let issues = identifyValidationIssues(block)
        let result = determineValidationResult(block, issues: issues)
        let confidence = calculateConfidence(block, issues: issues, result: result)
        
        return BlockValidation(
            block: block,
            result: result,
            confidence: confidence,
            issues: issues
        )
    }
    
    /// Validates multiple blocks and returns validation results
    func validateBlocks(_ blocks: [LayoutBlock]) -> [BlockValidation] {
        return blocks.map { validateBlock($0) }
    }
    
    // MARK: - Issue Identification
    
    private func identifyValidationIssues(_ block: LayoutBlock) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        
        // Check for multiple titles
        if hasMultipleTitles(block) {
            issues.append(ValidationIssue(
                type: .multipleTitles,
                description: "Block contains multiple title-like lines",
                severity: .high
            ))
        }
        
        // Check for multiple blank gaps
        if hasMultipleBlankGaps(block) {
            issues.append(ValidationIssue(
                type: .multipleBlankGaps,
                description: "Block contains multiple large spacing gaps",
                severity: .high
            ))
        }
        
        // Check for repeated numbering/bullets
        if hasRepeatedNumbering(block) {
            issues.append(ValidationIssue(
                type: .repeatedNumbering,
                description: "Block contains multiple numbered or bulleted items",
                severity: .medium
            ))
        }
        
        // Check for unusual length
        if isUnusuallyLong(block) {
            issues.append(ValidationIssue(
                type: .unusualLength,
                description: "Block is unusually long for a single joke",
                severity: .medium
            ))
        }
        
        // Check for topic shifts
        if hasTopicShifts(block) {
            issues.append(ValidationIssue(
                type: .topicShift,
                description: "Block appears to contain multiple unrelated topics",
                severity: .medium
            ))
        }
        
        // Check for structural ambiguity
        if hasStructuralAmbiguity(block) {
            issues.append(ValidationIssue(
                type: .structuralAmbiguity,
                description: "Block structure suggests multiple content sections",
                severity: .medium
            ))
        }
        
        // Check OCR confidence if applicable
        if hasLowOCRConfidence(block) {
            issues.append(ValidationIssue(
                type: .lowOCRConfidence,
                description: "Low OCR confidence may affect content accuracy",
                severity: .low
            ))
        }
        
        return issues
    }
    
    // MARK: - Specific Issue Checks
    
    private func hasMultipleTitles(_ block: LayoutBlock) -> Bool {
        let titleLikeLines = block.lines.filter { line in
            isLikelyTitle(line)
        }
        return titleLikeLines.count > 1
    }
    
    private func isLikelyTitle(_ line: ExtractedLine) -> Bool {
        let text = line.normalizedText
        
        // Short lines with title characteristics
        if text.count < 50 {
            // Ends with colon
            if text.hasSuffix(":") { return true }
            
            // All caps
            if text == text.uppercased() && text.rangeOfCharacter(from: .letters) != nil { return true }
            
            // Title case with multiple capitalized words
            let words = text.split(separator: " ")
            if words.count >= 2 && words.count <= 8 {
                let capitalizedCount = words.filter { $0.first?.isUppercase == true }.count
                if Float(capitalizedCount) / Float(words.count) > 0.6 {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func hasMultipleBlankGaps(_ block: LayoutBlock) -> Bool {
        let lines = block.lines
        guard lines.count > 2 else { return false }
        
        var largeGaps = 0
        
        for i in 1..<lines.count {
            let prevLine = lines[i-1]
            let currentLine = lines[i]
            
            let verticalGap = abs(currentLine.yPosition - prevLine.yPosition)
            let normalGap = currentLine.boundingBox.height * 1.5
            
            if verticalGap > normalGap * 2.0 {
                largeGaps += 1
            }
        }
        
        return largeGaps > 0 // Any internal large gap is suspicious
    }
    
    private func hasRepeatedNumbering(_ block: LayoutBlock) -> Bool {
        let numberedLines = block.lines.filter { line in
            let text = line.normalizedText
            return text.range(of: "^\\d+[.)]\\s", options: .regularExpression) != nil ||
                   text.hasPrefix("• ") || text.hasPrefix("- ") || text.hasPrefix("* ")
        }
        
        return numberedLines.count > 1
    }
    
    private func isUnusuallyLong(_ block: LayoutBlock) -> Bool {
        let text = block.text
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        
        // Most jokes are under 150 words
        return wordCount > 200
    }
    
    private func hasTopicShifts(_ block: LayoutBlock) -> Bool {
        let text = block.text
        
        // Look for abrupt topic changes indicated by certain phrases
        let topicShiftIndicators = [
            "anyway,", "moving on,", "speaking of", "on another note",
            "by the way,", "also,", "meanwhile,", "in other news"
        ]
        
        return topicShiftIndicators.contains { indicator in
            text.localizedCaseInsensitiveContains(indicator)
        }
    }
    
    private func hasStructuralAmbiguity(_ block: LayoutBlock) -> Bool {
        // Check for varying indentation levels that suggest multiple sections
        let indentLevels = Set(block.indentationPattern)
        if indentLevels.count > 2 {
            return true
        }
        
        // Check for lines that start like separate jokes
        let separateJokeStarters = block.lines.filter { line in
            let text = line.normalizedText.lowercased()
            return text.hasPrefix("so ") || text.hasPrefix("i ") || text.hasPrefix("my ") ||
                   text.hasPrefix("there's ") || text.hasPrefix("a guy ") || text.hasPrefix("why ")
        }
        
        return separateJokeStarters.count > 1
    }
    
    private func hasLowOCRConfidence(_ block: LayoutBlock) -> Bool {
        let ocrLines = block.lines.filter { $0.method == .visionOCR }
        guard !ocrLines.isEmpty else { return false }
        
        let averageConfidence = ocrLines.map(\.confidence).reduce(0, +) / Float(ocrLines.count)
        return averageConfidence < 0.7
    }
    
    // MARK: - Validation Result Determination
    
    private func determineValidationResult(_ block: LayoutBlock, issues: [ValidationIssue]) -> ValidationResult {
        let highSeverityIssues = issues.filter { $0.severity == .high }
        let mediumSeverityIssues = issues.filter { $0.severity == .medium }
        
        // High severity issues indicate likely multiple jokes
        if !highSeverityIssues.isEmpty {
            let suspectedCount = estimateJokeCount(block, issues: highSeverityIssues)
            return .multipleJokes(
                suspectedCount: suspectedCount,
                reasons: highSeverityIssues.map(\.description)
            )
        }
        
        // Medium severity issues require review
        if mediumSeverityIssues.count >= 2 {
            return .requiresReview(reasons: mediumSeverityIssues.map(\.description))
        }
        
        // Check if it looks like joke content
        if !looksLikeJokeContent(block) {
            return .notAJoke(reason: "Content doesn't appear to be joke material")
        }
        
        // Single medium issue still allows single joke classification but requires review
        if mediumSeverityIssues.count == 1 {
            return .requiresReview(reasons: mediumSeverityIssues.map(\.description))
        }
        
        // Passed all validation checks
        return .singleJoke
    }
    
    private func estimateJokeCount(_ block: LayoutBlock, issues: [ValidationIssue]) -> Int {
        var count = 1
        
        // Estimate based on issues found
        for issue in issues {
            switch issue.type {
            case .multipleTitles:
                let titleCount = block.lines.filter { isLikelyTitle($0) }.count
                count = max(count, titleCount)
            case .multipleBlankGaps:
                let gaps = countLargeGaps(block)
                count = max(count, gaps + 1)
            case .repeatedNumbering:
                let numberedLines = block.lines.filter { line in
                    line.normalizedText.range(of: "^\\d+[.)]\\s", options: .regularExpression) != nil
                }.count
                count = max(count, numberedLines)
            default:
                count = max(count, 2) // Conservative estimate
            }
        }
        
        return min(count, 5) // Cap at 5 for sanity
    }
    
    private func countLargeGaps(_ block: LayoutBlock) -> Int {
        let lines = block.lines
        guard lines.count > 1 else { return 0 }
        
        var gaps = 0
        
        for i in 1..<lines.count {
            let prevLine = lines[i-1]
            let currentLine = lines[i]
            
            let verticalGap = abs(currentLine.yPosition - prevLine.yPosition)
            let normalGap = currentLine.boundingBox.height * 1.5
            
            if verticalGap > normalGap * 2.0 {
                gaps += 1
            }
        }
        
        return gaps
    }
    
    private func looksLikeJokeContent(_ block: LayoutBlock) -> Bool {
        let text = block.text
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        
        // Too short or too long
        if wordCount < 5 || wordCount > 300 {
            return false
        }
        
        // Contains personal pronouns (common in jokes)
        let pronouns = ["I", "you", "my", "me", "we", "they", "he", "she"]
        let hasPronouns = pronouns.contains { pronoun in
            text.localizedCaseInsensitiveContains(" \(pronoun) ")
        }
        
        if hasPronouns { return true }
        
        // Contains dialogue or quotes
        if text.contains("\"") || text.contains("\u{201C}") || text.contains("said") {
            return true
        }
        
        // Contains humor setup words
        let setupWords = ["so", "there's", "walks into", "says", "asked"]
        let hasSetup = setupWords.contains { word in
            text.localizedCaseInsensitiveContains(word)
        }
        
        return hasSetup
    }
    
    // MARK: - Confidence Calculation
    
    private func calculateConfidence(_ block: LayoutBlock, issues: [ValidationIssue], result: ValidationResult) -> ImportConfidence {
        var confidenceScore: Float = 0.8 // Start with medium-high confidence
        
        // Deduct based on issues
        for issue in issues {
            switch issue.severity {
            case .high:
                confidenceScore -= 0.3
            case .medium:
                confidenceScore -= 0.15
            case .low:
                confidenceScore -= 0.05
            }
        }
        
        // Adjust based on validation result
        switch result {
        case .singleJoke:
            // Keep current confidence
            break
        case .multipleJokes:
            confidenceScore = 0.2 // Very low confidence for suspected multiple jokes
        case .requiresReview:
            confidenceScore = min(confidenceScore, 0.5) // Cap at medium-low
        case .notAJoke:
            confidenceScore = 0.1 // Very low confidence
        }
        
        // Boost confidence for clean structure
        if block.blockType == .singleJoke && issues.isEmpty {
            confidenceScore += 0.1
        }
        
        // OCR confidence factor
        let ocrLines = block.lines.filter { $0.method == .visionOCR }
        if !ocrLines.isEmpty {
            let avgOCRConfidence = ocrLines.map(\.confidence).reduce(0, +) / Float(ocrLines.count)
            confidenceScore *= avgOCRConfidence
        }
        
        // Convert to confidence level
        confidenceScore = max(0.0, min(1.0, confidenceScore))
        
        if confidenceScore >= ImportConfidence.high.threshold {
            return .high
        } else if confidenceScore >= ImportConfidence.medium.threshold {
            return .medium
        } else {
            return .low
        }
    }
    
    // MARK: - Block Splitting Suggestions
    
    /// Suggests how to split a block that contains multiple jokes
    func suggestSplitPoints(_ block: LayoutBlock) -> [Int] {
        var splitPoints: [Int] = []
        
        // Find title-like lines as split points
        for (index, line) in block.lines.enumerated() {
            if index > 0 && isLikelyTitle(line) {
                splitPoints.append(index)
            }
        }
        
        // Find large gap split points
        for i in 1..<block.lines.count {
            let prevLine = block.lines[i-1]
            let currentLine = block.lines[i]
            
            let verticalGap = abs(currentLine.yPosition - prevLine.yPosition)
            let normalGap = currentLine.boundingBox.height * 1.5
            
            if verticalGap > normalGap * 2.5 { // Even larger threshold for split suggestions
                splitPoints.append(i)
            }
        }
        
        // Find numbered/bulleted item split points
        for (index, line) in block.lines.enumerated() {
            if index > 0 {
                let text = line.normalizedText
                if text.range(of: "^\\d+[.)]\\s", options: .regularExpression) != nil ||
                   text.hasPrefix("• ") || text.hasPrefix("- ") {
                    splitPoints.append(index)
                }
            }
        }
        
        return Array(Set(splitPoints)).sorted()
    }
}
