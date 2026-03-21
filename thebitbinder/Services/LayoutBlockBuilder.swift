//
//  LayoutBlockBuilder.swift
//  thebitbinder
//
//  Deterministic layout-based joke boundary detection using spacing and structure
//

import Foundation
import CoreGraphics

/// The core component that builds joke candidate blocks based on layout analysis
/// This is designed to prevent multi-joke merging by using deterministic structural rules
final class LayoutBlockBuilder {
    
    static let shared = LayoutBlockBuilder()
    private init() {}
    
    /// Builds layout blocks from normalized pages using deterministic structural analysis
    func buildBlocks(from pages: [NormalizedPage]) -> [LayoutBlock] {
        var allBlocks: [LayoutBlock] = []
        var globalOrder = 0
        
        for page in pages {
            let pageBlocks = buildBlocksForPage(page, globalOrderOffset: globalOrder)
            allBlocks.append(contentsOf: pageBlocks)
            globalOrder += pageBlocks.count
        }
        
        return allBlocks
    }
    
    // MARK: - Page-Level Block Building
    
    private func buildBlocksForPage(_ page: NormalizedPage, globalOrderOffset: Int) -> [LayoutBlock] {
        let lines = page.lines
        guard !lines.isEmpty else { return [] }
        
        // First pass: identify structural separators
        let separators = identifyStructuralSeparators(lines)
        
        // Second pass: build blocks using separators
        let blocks = createBlocksFromSeparators(lines: lines, separators: separators, page: page, globalOrderOffset: globalOrderOffset)
        
        return blocks
    }
    
    // MARK: - Structural Separator Detection
    
    private func identifyStructuralSeparators(_ lines: [ExtractedLine]) -> [SeparatorPoint] {
        var separators: [SeparatorPoint] = []
        
        for i in 0..<lines.count {
            let currentLine = lines[i]
            let nextLine = i + 1 < lines.count ? lines[i + 1] : nil
            let prevLine = i > 0 ? lines[i - 1] : nil
            
            // Check for various separator types
            if let separator = detectSeparator(
                current: currentLine,
                previous: prevLine,
                next: nextLine,
                index: i
            ) {
                separators.append(separator)
            }
        }
        
        return separators.sorted { $0.position < $1.position }
    }
    
    private func detectSeparator(
        current: ExtractedLine,
        previous: ExtractedLine?,
        next: ExtractedLine?,
        index: Int
    ) -> SeparatorPoint? {
        
        // 1. Large vertical gap (strongest separator)
        if let prev = previous {
            let verticalGap = abs(current.yPosition - prev.yPosition)
            let expectedGap = Float(current.boundingBox.height) * 1.5 // Normal line spacing
            
            if verticalGap > expectedGap * 2.0 { // Significantly larger than normal
                return SeparatorPoint(
                    position: index,
                    type: .largeVerticalGap,
                    strength: .strong,
                    confidence: 0.9
                )
            }
        }
        
        // 2. Title detection (strong separator)
        if looksLikeTitle(current, next: next) {
            return SeparatorPoint(
                position: index,
                type: .titleDetected,
                strength: .strong,
                confidence: 0.8
            )
        }
        
        // 3. Bullet or number prefix (strong separator)
        if hasBulletOrNumberPrefix(current.normalizedText) {
            return SeparatorPoint(
                position: index,
                type: .bulletOrNumber,
                strength: .strong,
                confidence: 0.85
            )
        }
        
        // 4. Significant indentation change (medium separator)
        if let prev = previous {
            let indentChange = abs(current.indentationLevel - prev.indentationLevel)
            if indentChange >= 2 { // Significant indent change
                return SeparatorPoint(
                    position: index,
                    type: .indentationChange,
                    strength: .medium,
                    confidence: 0.6
                )
            }
        }
        
        // 5. Structural pattern change (medium separator)
        if detectStructuralChange(current: current, previous: previous, next: next) {
            return SeparatorPoint(
                position: index,
                type: .structuralChange,
                strength: .medium,
                confidence: 0.5
            )
        }
        
        return nil
    }
    
    // MARK: - Pattern Detection
    
    private func looksLikeTitle(_ line: ExtractedLine, next: ExtractedLine?) -> Bool {
        let text = line.normalizedText
        
        // Short lines followed by longer content
        if text.count < 50, let nextLine = next, nextLine.normalizedText.count > text.count + 20 {
            return true
        }
        
        // Lines ending with colon
        if text.hasSuffix(":") && text.count < 80 {
            return true
        }
        
        // ALL CAPS short lines
        if text == text.uppercased() && text.count < 60 && text.rangeOfCharacter(from: .letters) != nil {
            return true
        }
        
        // Title Case with most words capitalized
        let words = text.split(separator: " ")
        if words.count > 1 && words.count <= 8 {
            let capitalizedWords = words.filter { word in
                word.first?.isUppercase == true
            }
            if Float(capitalizedWords.count) / Float(words.count) > 0.7 {
                return true
            }
        }
        
        return false
    }
    
    private func hasBulletOrNumberPrefix(_ text: String) -> Bool {
        // Bullet points
        if text.hasPrefix("• ") || text.hasPrefix("- ") || text.hasPrefix("* ") {
            return true
        }
        
        // Numbered lists
        if text.range(of: "^\\d+[.)]\\s", options: .regularExpression) != nil {
            return true
        }
        
        // Lettered lists
        if text.range(of: "^[a-zA-Z][.)]\\s", options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    private func detectStructuralChange(
        current: ExtractedLine,
        previous: ExtractedLine?,
        next: ExtractedLine?
    ) -> Bool {
        
        // Font size change (if available)
        if let currentSize = current.estimatedFontSize,
           let prevSize = previous?.estimatedFontSize {
            let sizeDiff = abs(currentSize - prevSize)
            if sizeDiff > prevSize * 0.3 { // 30% size change
                return true
            }
        }
        
        // X-position shift (column change)
        if let prev = previous {
            let xDiff = abs(current.boundingBox.origin.x - prev.boundingBox.origin.x)
            if xDiff > 50 { // Significant horizontal shift
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Block Creation
    
    private func createBlocksFromSeparators(
        lines: [ExtractedLine],
        separators: [SeparatorPoint],
        page: NormalizedPage,
        globalOrderOffset: Int
    ) -> [LayoutBlock] {
        
        var blocks: [LayoutBlock] = []
        var currentStart = 0
        var orderInPage = 0
        
        for separator in separators {
            // Create block from current start to separator
            if separator.position > currentStart {
                let blockLines = Array(lines[currentStart..<separator.position])
                if !blockLines.isEmpty {
                    let block = createBlock(
                        lines: blockLines,
                        separatorBefore: orderInPage == 0 ? nil : .structuralChange, // First block has no separator before
                        separatorAfter: separator.type,
                        pageNumber: page.pageNumber,
                        orderInPage: orderInPage
                    )
                    blocks.append(block)
                    orderInPage += 1
                }
            }
            
            currentStart = separator.position
        }
        
        // Create final block from last separator to end
        if currentStart < lines.count {
            let blockLines = Array(lines[currentStart..<lines.count])
            if !blockLines.isEmpty {
                let block = createBlock(
                    lines: blockLines,
                    separatorBefore: separators.isEmpty ? nil : separators.last?.type,
                    separatorAfter: nil, // Last block has no separator after
                    pageNumber: page.pageNumber,
                    orderInPage: orderInPage
                )
                blocks.append(block)
            }
        }
        
        return blocks.map { block in
            // Analyze each block to determine its type
            let analyzedType = analyzeBlockType(block)
            return LayoutBlock(
                lines: block.lines,
                blockType: analyzedType,
                separatorBefore: block.separatorBefore,
                separatorAfter: block.separatorAfter,
                averageLineSpacing: block.averageLineSpacing,
                totalHeight: block.totalHeight,
                indentationPattern: block.indentationPattern,
                containsTitle: block.containsTitle,
                pageNumber: block.pageNumber,
                orderInPage: block.orderInPage
            )
        }
    }
    
    private func createBlock(
        lines: [ExtractedLine],
        separatorBefore: BlockSeparationType?,
        separatorAfter: BlockSeparationType?,
        pageNumber: Int,
        orderInPage: Int
    ) -> LayoutBlock {
        
        let averageLineSpacing = calculateAverageLineSpacing(lines)
        let totalHeight = calculateTotalHeight(lines)
        let indentationPattern = lines.map { $0.indentationLevel }
        let containsTitle = lines.contains { line in
            looksLikeTitle(line, next: nil) // Simplified check for block creation
        }
        
        return LayoutBlock(
            lines: lines,
            blockType: .unknown, // Will be determined in analysis phase
            separatorBefore: separatorBefore,
            separatorAfter: separatorAfter,
            averageLineSpacing: averageLineSpacing,
            totalHeight: totalHeight,
            indentationPattern: indentationPattern,
            containsTitle: containsTitle,
            pageNumber: pageNumber,
            orderInPage: orderInPage
        )
    }
    
    // MARK: - Block Analysis
    
    private func analyzeBlockType(_ block: LayoutBlock) -> BlockType {
        let text = block.text
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        
        // Very short blocks might be titles or metadata
        if wordCount < 5 && block.lines.count == 1 {
            return .title
        }
        
        // Check for multiple joke indicators within the block
        if hasSuspeciousMultiJokePatterns(block) {
            return .suspectedMultipleJokes
        }
        
        // Check if it looks like actual joke content
        if looksLikeJokeContent(text) {
            return .singleJoke
        }
        
        // Check if it's metadata or notes
        if looksLikeMetadata(text) {
            return .metadata
        }
        
        if looksLikeNote(text) {
            return .note
        }
        
        return .unknown
    }
    
    private func hasSuspeciousMultiJokePatterns(_ block: LayoutBlock) -> Bool {
        let text = block.text
        
        // Multiple title-like lines within one block
        let titleLikeLines = block.lines.filter { looksLikeTitle($0, next: nil) }
        if titleLikeLines.count > 1 {
            return true
        }
        
        // Multiple bullet/number sequences
        let bulletLines = block.lines.filter { hasBulletOrNumberPrefix($0.normalizedText) }
        if bulletLines.count > 1 {
            return true
        }
        
        // Unusually long blocks (might be multiple jokes merged)
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount > 200 { // Arbitrary threshold - most jokes are shorter
            return true
        }
        
        // Multiple large gaps within the block (should have been split earlier)
        if hasInternalLargeGaps(block) {
            return true
        }
        
        return false
    }
    
    private func hasInternalLargeGaps(_ block: LayoutBlock) -> Bool {
        let lines = block.lines
        guard lines.count > 1 else { return false }
        
        var largeGaps = 0
        
        for i in 1..<lines.count {
            let prevLine = lines[i - 1]
            let currentLine = lines[i]
            
            let gap = abs(currentLine.yPosition - prevLine.yPosition)
            let expectedGap = Float(currentLine.boundingBox.height) * 1.5
            
            if gap > expectedGap * 2.0 {
                largeGaps += 1
            }
        }
        
        return largeGaps > 0 // Any large gap within a block is suspicious
    }
    
    private func looksLikeJokeContent(_ text: String) -> Bool {
        // Heuristics for identifying joke content
        let words = text.split(whereSeparator: \.isWhitespace)
        
        // Reasonable length for a joke
        if words.count < 5 || words.count > 200 {
            return false
        }
        
        // Contains conversational language
        let conversationalWords = ["I", "you", "my", "me", "we", "they", "said", "told", "asked"]
        let hasConversational = conversationalWords.contains { word in
            text.localizedCaseInsensitiveContains(word)
        }
        
        if hasConversational { return true }
        
        // Contains humor indicators
        let humorIndicators = ["funny", "laugh", "joke", "hilarious", "ridiculous"]
        let hasHumor = humorIndicators.contains { indicator in
            text.localizedCaseInsensitiveContains(indicator)
        }
        
        if hasHumor { return true }
        
        // Has dialogue or quoted speech
        if text.contains("\"") || text.contains("\u{201C}") || text.contains("\u{201D}") {
            return true
        }
        
        return false
    }
    
    private func looksLikeMetadata(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let metadata = ["date:", "venue:", "audience:", "time:", "location:", "notes:"]
        return metadata.contains { lowercased.contains($0) }
    }
    
    private func looksLikeNote(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let noteIndicators = ["note:", "remember:", "todo:", "fix:", "work on:"]
        return noteIndicators.contains { lowercased.contains($0) }
    }
    
    // MARK: - Helper Calculations
    
    private func calculateAverageLineSpacing(_ lines: [ExtractedLine]) -> Float {
        guard lines.count > 1 else { return 0 }
        
        var totalSpacing: Float = 0
        for i in 1..<lines.count {
            let spacing = abs(lines[i].yPosition - lines[i-1].yPosition)
            totalSpacing += spacing
        }
        
        return totalSpacing / Float(lines.count - 1)
    }
    
    private func calculateTotalHeight(_ lines: [ExtractedLine]) -> Float {
        guard !lines.isEmpty else { return 0 }
        
        let minY = lines.map(\.yPosition).min() ?? 0
        let maxY = lines.map { $0.yPosition + Float($0.boundingBox.height) }.max() ?? 0
        
        return maxY - minY
    }
}

// MARK: - Supporting Types

private struct SeparatorPoint {
    let position: Int // Line index
    let type: BlockSeparationType
    let strength: SeparatorStrength
    let confidence: Float
}

private enum SeparatorStrength {
    case weak
    case medium
    case strong
}
