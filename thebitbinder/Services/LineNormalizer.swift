//
//  LineNormalizer.swift
//  thebitbinder
//
//  Line-level text normalization and cleaning with layout preservation
//

import Foundation
import CoreGraphics

/// Normalizes extracted text lines while preserving layout and positional information
final class LineNormalizer {
    
    static let shared = LineNormalizer()
    private init() {}
    
    /// Normalizes pages by cleaning text and removing headers/footers
    func normalizePages(_ pages: [NormalizedPage]) -> [NormalizedPage] {
        return pages.map { page in
            let cleanedLines = cleanLines(page.lines, page: page)
            let filteredLines = removeRepeatingElements(cleanedLines, page: page)
            
            return NormalizedPage(
                pageNumber: page.pageNumber,
                lines: filteredLines,
                hasRepeatingHeader: page.hasRepeatingHeader,
                hasRepeatingFooter: page.hasRepeatingFooter,
                averageLineHeight: page.averageLineHeight,
                pageHeight: page.pageHeight
            )
        }
    }
    
    // MARK: - Line Cleaning
    
    private func cleanLines(_ lines: [ExtractedLine], page: NormalizedPage) -> [ExtractedLine] {
        return lines.compactMap { line in
            let cleanedText = cleanLineText(line.normalizedText)
            
            // Skip completely empty lines or noise
            guard !cleanedText.isEmpty, !isNoise(cleanedText) else { return nil }
            
            return ExtractedLine(
                rawText: line.rawText,
                normalizedText: cleanedText,
                pageNumber: line.pageNumber,
                lineNumber: line.lineNumber,
                boundingBox: line.boundingBox,
                confidence: line.confidence,
                estimatedFontSize: line.estimatedFontSize,
                indentationLevel: calculateCleanedIndentationLevel(cleanedText),
                yPosition: line.yPosition,
                method: line.method
            )
        }
    }
    
    private func cleanLineText(_ text: String) -> String {
        var cleaned = text
        
        // Remove excessive whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Fix common OCR punctuation errors
        cleaned = fixPunctuation(cleaned)
        
        // Fix hyphenated line breaks (if this line ends with a hyphen and no punctuation)
        if cleaned.hasSuffix("-") && !cleaned.hasSuffix("--") && !hasTerminalPunctuation(cleaned.dropLast()) {
            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        
        return cleaned
    }
    
    private func fixPunctuation(_ text: String) -> String {
        var fixed = text
        
        // Fix spaced punctuation
        fixed = fixed.replacingOccurrences(of: " \\.", with: ".", options: .regularExpression)
        fixed = fixed.replacingOccurrences(of: " ,", with: ",", options: .regularExpression)
        fixed = fixed.replacingOccurrences(of: " !", with: "!", options: .regularExpression)
        fixed = fixed.replacingOccurrences(of: " \\?", with: "?", options: .regularExpression)
        
        // Fix quotation marks
        fixed = fixed.replacingOccurrences(of: " \"", with: " \u{201C}", options: .regularExpression)
        fixed = fixed.replacingOccurrences(of: "\" ", with: "\u{201D} ", options: .regularExpression)
        
        // Fix apostrophes (common OCR error)
        fixed = fixed.replacingOccurrences(of: "'", with: "'")
        
        return fixed
    }
    
    private func hasTerminalPunctuation(_ text: String.SubSequence) -> Bool {
        let terminals: Set<Character> = [".", "!", "?", ":", ";"]
        return text.last.map { terminals.contains($0) } ?? false
    }
    
    private func calculateCleanedIndentationLevel(_ text: String) -> Int {
        // Recalculate indentation after cleaning
        var leadingSpaces = 0
        for char in text {
            if char == " " {
                leadingSpaces += 1
            } else {
                break
            }
        }
        return leadingSpaces / 4
    }
    
    // MARK: - Noise Detection
    
    private func isNoise(_ text: String) -> Bool {
        // Skip very short fragments that are likely noise
        if text.count < 2 { return true }
        
        // Skip lines with mostly symbols or numbers without context
        let letters = text.filter { $0.isLetter }
        if letters.count < text.count / 3 { return true }
        
        // Skip obvious page elements
        if isPageElement(text) { return true }
        
        // Skip repeated characters (scanning artifacts)
        if isRepeatedCharacters(text) { return true }
        
        return false
    }
    
    private func isPageElement(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Common page elements to filter out
        let pageElements = [
            "page", "continued", "end", "start", "header", "footer",
            "copyright", "©", "all rights reserved", "confidential"
        ]
        
        return pageElements.contains { lowercased.contains($0) }
    }
    
    private func isRepeatedCharacters(_ text: String) -> Bool {
        guard text.count > 3 else { return false }
        
        // Check if line is mostly the same character repeated
        let characters = Array(text.filter { !$0.isWhitespace })
        guard !characters.isEmpty else { return false }
        
        let firstChar = characters.first!
        let sameCharCount = characters.filter { $0 == firstChar }.count
        
        return Float(sameCharCount) / Float(characters.count) > 0.8
    }
    
    // MARK: - Header/Footer Removal
    
    private func removeRepeatingElements(_ lines: [ExtractedLine], page: NormalizedPage) -> [ExtractedLine] {
        var filtered = lines
        
        // Remove identified headers
        if page.hasRepeatingHeader {
            filtered = removeHeaderLines(filtered)
        }
        
        // Remove identified footers
        if page.hasRepeatingFooter {
            filtered = removeFooterLines(filtered)
        }
        
        // Remove page numbers and similar elements
        filtered = removePageNumbers(filtered)
        
        return filtered
    }
    
    private func removeHeaderLines(_ lines: [ExtractedLine]) -> [ExtractedLine] {
        guard lines.count > 2 else { return lines }
        
        // Remove top 1-2 lines if they appear to be headers
        let potentialContent = lines.dropFirst(2)
        
        // Check if removing the top lines leaves substantial content
        if potentialContent.count >= lines.count / 2 {
            // Verify the top lines are really headers by checking for header patterns
            let topLines = Array(lines.prefix(2))
            if topLines.allSatisfy(looksLikeHeader) {
                return Array(potentialContent)
            }
        }
        
        return lines
    }
    
    private func removeFooterLines(_ lines: [ExtractedLine]) -> [ExtractedLine] {
        guard lines.count > 2 else { return lines }
        
        // Remove bottom 1-2 lines if they appear to be footers
        let potentialContent = lines.dropLast(2)
        
        if potentialContent.count >= lines.count / 2 {
            let bottomLines = Array(lines.suffix(2))
            if bottomLines.allSatisfy(looksLikeFooter) {
                return Array(potentialContent)
            }
        }
        
        return lines
    }
    
    private func looksLikeHeader(_ line: ExtractedLine) -> Bool {
        let text = line.normalizedText.lowercased()
        
        // Common header patterns
        if text.contains("page") || text.contains("chapter") || text.contains("section") {
            return true
        }
        
        // Very short lines at the top might be headers
        if line.normalizedText.count < 30 && line.lineNumber <= 2 {
            return true
        }
        
        return false
    }
    
    private func looksLikeFooter(_ line: ExtractedLine) -> Bool {
        let text = line.normalizedText.lowercased()
        
        // Common footer patterns
        if text.contains("page") || text.contains("copyright") || text.contains("©") {
            return true
        }
        
        // Lines that are mostly numbers (page numbers)
        let numbers = text.filter { $0.isNumber }
        if numbers.count > text.count / 2 && text.count < 10 {
            return true
        }
        
        return false
    }
    
    private func removePageNumbers(_ lines: [ExtractedLine]) -> [ExtractedLine] {
        return lines.filter { line in
            let text = line.normalizedText.trimmingCharacters(in: .whitespaces)
            
            // Skip standalone numbers (likely page numbers)
            if text.allSatisfy(\.isNumber) && text.count <= 3 {
                return false
            }
            
            // Skip "Page X" patterns
            if text.lowercased().hasPrefix("page ") && text.count < 10 {
                return false
            }
            
            return true
        }
    }
}

// MARK: - Line Merging for Continued Text

extension LineNormalizer {
    
    /// Merges lines that were split by layout but should be continuous
    func mergeFragmentedLines(_ lines: [ExtractedLine]) -> [ExtractedLine] {
        var merged: [ExtractedLine] = []
        var i = 0
        
        while i < lines.count {
            let currentLine = lines[i]
            
            // Look ahead for continuation
            if i + 1 < lines.count {
                let nextLine = lines[i + 1]
                
                if shouldMergeLines(currentLine, nextLine) {
                    let mergedLine = mergeLines(currentLine, nextLine)
                    merged.append(mergedLine)
                    i += 2 // Skip both lines
                    continue
                }
            }
            
            merged.append(currentLine)
            i += 1
        }
        
        return merged
    }
    
    private func shouldMergeLines(_ line1: ExtractedLine, _ line2: ExtractedLine) -> Bool {
        // Only merge lines from the same page
        guard line1.pageNumber == line2.pageNumber else { return false }
        
        // Don't merge if there's a large gap between lines
        let verticalGap = abs(line1.yPosition - line2.yPosition)
        if verticalGap > line1.boundingBox.height * 2 { return false }
        
        // Don't merge if indentation changes significantly
        let indentDiff = abs(line1.indentationLevel - line2.indentationLevel)
        if indentDiff > 1 { return false }
        
        // Merge if first line doesn't end with terminal punctuation
        // and second line doesn't start like a new sentence/bullet
        let text1 = line1.normalizedText
        let text2 = line2.normalizedText
        
        let endsWithTerminal = hasTerminalPunctuation(text1[text1.startIndex..<text1.endIndex])
        let startsLikeNewSentence = text2.first?.isUppercase == true || 
                                  text2.hasPrefix("•") || 
                                  text2.hasPrefix("-") ||
                                  text2.range(of: "^\\d+[.)]", options: .regularExpression) != nil
        
        return !endsWithTerminal && !startsLikeNewSentence
    }
    
    private func mergeLines(_ line1: ExtractedLine, _ line2: ExtractedLine) -> ExtractedLine {
        let mergedText = line1.normalizedText + " " + line2.normalizedText
        
        // Create combined bounding box
        let combinedBox = line1.boundingBox.union(line2.boundingBox)
        
        // Use the average confidence
        let averageConfidence = (line1.confidence + line2.confidence) / 2
        
        return ExtractedLine(
            rawText: line1.rawText + "\n" + line2.rawText,
            normalizedText: mergedText,
            pageNumber: line1.pageNumber,
            lineNumber: line1.lineNumber,
            boundingBox: combinedBox,
            confidence: averageConfidence,
            estimatedFontSize: line1.estimatedFontSize,
            indentationLevel: line1.indentationLevel,
            yPosition: line1.yPosition,
            method: line1.method
        )
    }
}
