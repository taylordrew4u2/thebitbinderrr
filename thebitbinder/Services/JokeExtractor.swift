//
//  JokeExtractor.swift
//  thebitbinder
//
//  Extracts final joke objects from validated layout blocks
//

import Foundation

/// Extracts joke objects from validated layout blocks
final class JokeExtractor {
    
    static let shared = JokeExtractor()
    private let titleDetector = TitleDetector()
    
    private init() {}
    
    /// Extracts a joke object from a validated block
    func extractJoke(from validation: BlockValidation, sourceFile: String) -> ImportedJoke? {
        let block = validation.block
        
        // Only extract from blocks that passed validation or need review
        switch validation.result {
        case .singleJoke, .requiresReview:
            break
        case .multipleJokes, .notAJoke:
            return nil
        }
        
        let titleInfo = titleDetector.extractTitle(from: block)
        let bodyText = extractBody(from: block, titleInfo: titleInfo)
        let tags = extractTags(from: block)
        let confidenceFactors = calculateConfidenceFactors(block, validation: validation)
        
        let sourceMetadata = ImportSourceMetadata(
            fileName: sourceFile,
            pageNumber: block.pageNumber,
            orderInPage: block.orderInPage,
            orderInFile: 0, // Will be set by pipeline coordinator
            boundingBox: calculateCombinedBoundingBox(block.lines),
            importTimestamp: Date()
        )
        
        return ImportedJoke(
            title: titleInfo.title,
            body: bodyText,
            rawSourceText: block.rawText,
            tags: tags,
            confidence: confidenceFactors.importConfidence,
            confidenceFactors: confidenceFactors,
            sourceMetadata: sourceMetadata,
            validationResult: validation.result,
            extractionMethod: block.lines.first?.method ?? .visionOCR
        )
    }
    
    // MARK: - Title Extraction
    
    private func extractBody(from block: LayoutBlock, titleInfo: TitleInfo) -> String {
        guard let title = titleInfo.title, let titleLineIndex = titleInfo.lineIndex else {
            // No title found, use entire block as body
            return block.text
        }
        
        // Remove title line and use rest as body
        let bodyLines = Array(block.lines.dropFirst(titleLineIndex + 1))
        let bodyText = bodyLines.map(\.normalizedText).joined(separator: "\n")
        
        return bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Tag Extraction
    
    private func extractTags(from block: LayoutBlock) -> [String] {
        var tags: [String] = []
        let text = block.text.lowercased()
        
        // Extract topic-based tags
        tags.append(contentsOf: extractTopicTags(text))
        
        // Extract style-based tags
        tags.append(contentsOf: extractStyleTags(text))
        
        // Extract structure-based tags
        tags.append(contentsOf: extractStructureTags(block))
        
        return Array(Set(tags)) // Remove duplicates
    }
    
    private func extractTopicTags(_ text: String) -> [String] {
        var tags: [String] = []
        
        let topicKeywords = [
            "family": ["wife", "husband", "kids", "children", "mother", "father", "mom", "dad"],
            "relationships": ["dating", "girlfriend", "boyfriend", "marriage", "divorce", "tinder"],
            "work": ["job", "boss", "office", "work", "coworker", "meeting"],
            "technology": ["phone", "computer", "internet", "social media", "facebook", "twitter"],
            "travel": ["airport", "flight", "hotel", "vacation", "uber", "taxi"],
            "food": ["restaurant", "cooking", "food", "pizza", "coffee"],
            "pets": ["dog", "cat", "pet", "animal"],
            "health": ["doctor", "hospital", "diet", "exercise", "gym"],
            "money": ["money", "broke", "expensive", "cheap", "credit card"]
        ]
        
        for (tag, keywords) in topicKeywords {
            if keywords.contains(where: { text.contains($0) }) {
                tags.append(tag)
            }
        }
        
        return tags
    }
    
    private func extractStyleTags(_ text: String) -> [String] {
        var tags: [String] = []
        
        // Observational comedy
        if text.contains("ever notice") || text.contains("why do") || text.contains("what's the deal") {
            tags.append("observational")
        }
        
        // Self-deprecating
        if text.contains("i'm so") || text.contains("i can't") || text.contains("i'm the kind of") {
            tags.append("self-deprecating")
        }
        
        // Storytelling
        if text.contains("so i was") || text.contains("the other day") || text.contains("this one time") {
            tags.append("story")
        }
        
        // One-liners
        if text.split(separator: ".").count <= 2 && text.count < 100 {
            tags.append("one-liner")
        }
        
        return tags
    }
    
    private func extractStructureTags(_ block: LayoutBlock) -> [String] {
        var tags: [String] = []
        
        let wordCount = block.text.split(whereSeparator: \.isWhitespace).count
        
        // Length-based tags
        if wordCount < 30 {
            tags.append("short")
        } else if wordCount > 100 {
            tags.append("long")
        }
        
        // Structure-based tags
        if block.containsTitle {
            tags.append("titled")
        }
        
        if block.text.contains("\"") {
            tags.append("dialogue")
        }
        
        return tags
    }
    
    // MARK: - Confidence Factors Calculation
    
    private func calculateConfidenceFactors(_ block: LayoutBlock, validation: BlockValidation) -> ConfidenceFactors {
        let extractionQuality = calculateExtractionQuality(block)
        let structuralCleanliness = calculateStructuralCleanliness(block, validation: validation)
        let titleDetection = calculateTitleDetectionScore(block)
        let boundaryClarity = calculateBoundaryClarity(block)
        let ocrConfidence = calculateOCRConfidence(block)
        
        return ConfidenceFactors(
            extractionQuality: extractionQuality,
            structuralCleanliness: structuralCleanliness,
            titleDetection: titleDetection,
            boundaryClarity: boundaryClarity,
            ocrConfidence: ocrConfidence
        )
    }
    
    private func calculateExtractionQuality(_ block: LayoutBlock) -> Float {
        var score: Float = 0.8 // Base score
        
        // Boost for consistent extraction method
        let methods = Set(block.lines.map(\.method))
        if methods.count == 1 {
            score += 0.1
        }
        
        // Boost for reasonable length
        let wordCount = block.text.split(whereSeparator: \.isWhitespace).count
        if wordCount >= 10 && wordCount <= 150 {
            score += 0.1
        } else {
            score -= 0.2
        }
        
        return max(0.0, min(1.0, score))
    }
    
    private func calculateStructuralCleanliness(_ block: LayoutBlock, validation: BlockValidation) -> Float {
        var score: Float = 1.0
        
        // Penalize for validation issues
        for issue in validation.issues {
            switch issue.severity {
            case .high:
                score -= 0.4
            case .medium:
                score -= 0.2
            case .low:
                score -= 0.1
            }
        }
        
        return max(0.0, min(1.0, score))
    }
    
    private func calculateTitleDetectionScore(_ block: LayoutBlock) -> Float {
        let titleInfo = titleDetector.extractTitle(from: block)
        
        if titleInfo.title != nil {
            return titleInfo.confidence
        } else {
            return 0.3 // Low but not zero - absence of title is not necessarily bad
        }
    }
    
    private func calculateBoundaryClarity(_ block: LayoutBlock) -> Float {
        var score: Float = 0.7 // Base score
        
        // Boost for strong separators
        if let separator = block.separatorBefore {
            switch separator {
            case .largeVerticalGap, .titleDetected, .bulletOrNumber:
                score += 0.15
            case .indentationChange, .pageBreak, .structuralChange:
                score += 0.05
            }
        }
        
        if let separator = block.separatorAfter {
            switch separator {
            case .largeVerticalGap, .titleDetected, .bulletOrNumber:
                score += 0.15
            case .indentationChange, .pageBreak, .structuralChange:
                score += 0.05
            }
        }
        
        return max(0.0, min(1.0, score))
    }
    
    private func calculateOCRConfidence(_ block: LayoutBlock) -> Float {
        let ocrLines = block.lines.filter { $0.method == .visionOCR }
        
        if ocrLines.isEmpty {
            return 1.0 // Perfect confidence for non-OCR text
        }
        
        let averageConfidence = ocrLines.map(\.confidence).reduce(0, +) / Float(ocrLines.count)
        return averageConfidence
    }
    
    // MARK: - Helper Methods
    
    private func calculateCombinedBoundingBox(_ lines: [ExtractedLine]) -> CGRect? {
        guard !lines.isEmpty else { return nil }
        
        let boxes = lines.map(\.boundingBox)
        
        let minX = boxes.map(\.minX).min() ?? 0
        let minY = boxes.map(\.minY).min() ?? 0
        let maxX = boxes.map(\.maxX).max() ?? 0
        let maxY = boxes.map(\.maxY).max() ?? 0
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Title Detector

private class TitleDetector {
    
    struct TitleInfo {
        let title: String?
        let lineIndex: Int?
        let confidence: Float
    }
    
    func extractTitle(from block: LayoutBlock) -> TitleInfo {
        let lines = block.lines
        
        // Look for title in first few lines
        for (index, line) in lines.prefix(3).enumerated() {
            if let titleCandidate = analyzeLineForTitle(line, context: lines) {
                return TitleInfo(
                    title: titleCandidate.title,
                    lineIndex: index,
                    confidence: titleCandidate.confidence
                )
            }
        }
        
        return TitleInfo(title: nil, lineIndex: nil, confidence: 0.0)
    }
    
    private func analyzeLineForTitle(_ line: ExtractedLine, context: [ExtractedLine]) -> (title: String, confidence: Float)? {
        let text = line.normalizedText
        
        // Too long to be a title
        if text.count > 80 { return nil }
        
        var confidence: Float = 0.0
        
        // Boost for short lines
        if text.count < 50 {
            confidence += 0.3
        }
        
        // Boost for ending with colon
        if text.hasSuffix(":") {
            confidence += 0.4
            let cleanTitle = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
            return (cleanTitle, confidence)
        }
        
        // Boost for all caps
        if text == text.uppercased() && text.rangeOfCharacter(from: .letters) != nil {
            confidence += 0.3
        }
        
        // Boost for title case
        let words = text.split(separator: " ")
        if words.count >= 2 && words.count <= 8 {
            let capitalizedWords = words.filter { $0.first?.isUppercase == true }
            if Float(capitalizedWords.count) / Float(words.count) > 0.6 {
                confidence += 0.2
            }
        }
        
        // Boost if followed by longer content
        if context.count > 1 {
            let nextLine = context[1]
            if nextLine.normalizedText.count > text.count + 20 {
                confidence += 0.1
            }
        }
        
        if confidence >= 0.4 {
            return (text, confidence)
        }
        
        return nil
    }
}