//
//  PDFTextExtractor.swift
//  thebitbinder
//
//  Enhanced PDF text extraction with line-level metadata
//

import Foundation
import PDFKit
import CoreGraphics

/// Enhanced PDF text extraction that preserves layout and positioning information
final class PDFTextExtractor {
    
    static let shared = PDFTextExtractor()
    private init() {}
    
    func extractPages(from url: URL) async throws -> [NormalizedPage] {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.invalidDocument
        }
        
        var pages: [NormalizedPage] = []
        let pageCount = document.pageCount
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            
            let extractedPage = await extractPageWithLayout(page: page, pageNumber: i + 1)
            pages.append(extractedPage)
        }
        
        // Post-process to identify repeating headers/footers
        let processedPages = identifyRepeatingElements(pages: pages)
        
        return processedPages
    }
    
    private func extractPageWithLayout(page: PDFPage, pageNumber: Int) async -> NormalizedPage {
        let pageText = page.string ?? ""
        let pageBounds = page.bounds(for: .mediaBox)
        
        // Split into lines and estimate positioning
        let rawLines = pageText.components(separatedBy: .newlines)
        var extractedLines: [ExtractedLine] = []
        
        let averageLineHeight = estimateAverageLineHeight(for: pageBounds)
        var currentY: Float = Float(pageBounds.height)
        
        for (index, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                currentY -= averageLineHeight
                continue
            }
            
            // Estimate bounding box (PDFKit doesn't give us exact positioning without more complex analysis)
            let estimatedHeight = averageLineHeight
            let estimatedWidth = Float(trimmed.count) * 8.0 // Rough character width estimate
            let indentLevel = calculateIndentationLevel(rawLine)
            let xPosition = Float(indentLevel * 20) // Rough indent estimate
            
            let boundingBox = CGRect(
                x: CGFloat(xPosition),
                y: CGFloat(currentY - estimatedHeight),
                width: CGFloat(estimatedWidth),
                height: CGFloat(estimatedHeight)
            )
            
            let extractedLine = ExtractedLine(
                rawText: rawLine,
                normalizedText: trimmed,
                pageNumber: pageNumber,
                lineNumber: index + 1,
                boundingBox: boundingBox,
                confidence: 1.0, // PDFKit text is always high confidence
                estimatedFontSize: nil, // Could be enhanced with text analysis
                indentationLevel: indentLevel,
                yPosition: currentY,
                method: .pdfKitText
            )
            
            extractedLines.append(extractedLine)
            currentY -= averageLineHeight
        }
        
        return NormalizedPage(
            pageNumber: pageNumber,
            lines: extractedLines,
            hasRepeatingHeader: false, // Will be determined later
            hasRepeatingFooter: false, // Will be determined later
            averageLineHeight: averageLineHeight,
            pageHeight: Float(pageBounds.height)
        )
    }
    
    private func estimateAverageLineHeight(for bounds: CGRect) -> Float {
        // Rough estimate based on page size - could be improved with font analysis
        return max(12.0, Float(bounds.height) / 50.0)
    }
    
    private func calculateIndentationLevel(_ line: String) -> Int {
        var spaces = 0
        for char in line {
            if char == " " {
                spaces += 1
            } else if char == "\t" {
                spaces += 4 // Treat tabs as 4 spaces
            } else {
                break
            }
        }
        return spaces / 4 // Each 4 spaces = 1 indent level
    }
    
    private func identifyRepeatingElements(pages: [NormalizedPage]) -> [NormalizedPage] {
        guard pages.count > 1 else { return pages }
        
        // Find potential headers (top 2 lines of each page)
        var potentialHeaders: [String] = []
        var potentialFooters: [String] = []
        
        for page in pages {
            if let firstLine = page.lines.first?.normalizedText {
                potentialHeaders.append(firstLine)
            }
            if let secondLine = page.lines.dropFirst().first?.normalizedText {
                potentialHeaders.append(secondLine)
            }
            
            if let lastLine = page.lines.last?.normalizedText {
                potentialFooters.append(lastLine)
            }
            if page.lines.count > 1, let secondLastLine = page.lines.dropLast().last?.normalizedText {
                potentialFooters.append(secondLastLine)
            }
        }
        
        // Find most common headers/footers
        let headerCounts = Dictionary(grouping: potentialHeaders, by: { $0 }).mapValues { $0.count }
        let footerCounts = Dictionary(grouping: potentialFooters, by: { $0 }).mapValues { $0.count }
        
        let repeatingHeader = headerCounts.first { $0.value >= pages.count / 2 }?.key
        let repeatingFooter = footerCounts.first { $0.value >= pages.count / 2 }?.key
        
        // Mark pages with identified headers/footers
        return pages.map { page in
            let hasHeader = repeatingHeader != nil && 
                           (page.lines.first?.normalizedText == repeatingHeader || 
                            page.lines.dropFirst().first?.normalizedText == repeatingHeader)
            
            let hasFooter = repeatingFooter != nil && 
                           (page.lines.last?.normalizedText == repeatingFooter || 
                            page.lines.dropLast().last?.normalizedText == repeatingFooter)
            
            return NormalizedPage(
                pageNumber: page.pageNumber,
                lines: page.lines,
                hasRepeatingHeader: hasHeader,
                hasRepeatingFooter: hasFooter,
                averageLineHeight: page.averageLineHeight,
                pageHeight: page.pageHeight
            )
        }
    }
}

enum ExtractionError: Error {
    case invalidDocument
    case noTextFound
    case processingFailed
}
