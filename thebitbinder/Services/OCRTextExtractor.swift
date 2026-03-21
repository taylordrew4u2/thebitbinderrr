//
//  OCRTextExtractor.swift
//  thebitbinder
//
//  Enhanced OCR extraction with line-level metadata and confidence scoring
//

import Foundation
import Vision
import VisionKit
import UIKit
import PDFKit

/// Enhanced OCR text extraction that preserves layout, positioning, and confidence information
final class OCRTextExtractor {
    
    static let shared = OCRTextExtractor()
    private let customWordsProvider = OCRCustomWordsProvider()
    
    private init() {}
    
    // MARK: - PDF OCR Extraction
    
    func extractFromPDF(url: URL) async throws -> [NormalizedPage] {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.invalidDocument
        }
        
        var pages: [NormalizedPage] = []
        let pageCount = document.pageCount
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            
            if let image = convertPDFPageToImage(page) {
                let extractedPage = try await extractFromImage(image, pageNumber: i + 1)
                pages.append(extractedPage)
            }
        }
        
        return identifyRepeatingElements(pages: pages)
    }
    
    // MARK: - Image OCR Extraction
    
    func extractFromImage(_ image: UIImage, pageNumber: Int = 1) async throws -> NormalizedPage {
        guard let cgImage = image.cgImage else {
            throw ExtractionError.invalidImage
        }
        
        let customWords = await customWordsProvider.getCustomWords()
        
        // Configure high-quality OCR request
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        
        // Set custom words if available
        if !customWords.allWords.isEmpty {
            request.customWords = customWords.allWords
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        try requestHandler.perform([request])
        
        guard let observations = request.results, !observations.isEmpty else {
            // Fallback to fast recognition
            return try await fallbackExtraction(cgImage: cgImage, pageNumber: pageNumber, customWords: customWords)
        }
        
        let extractedLines = processVisionResults(observations, image: image, pageNumber: pageNumber)
        
        return NormalizedPage(
            pageNumber: pageNumber,
            lines: extractedLines,
            hasRepeatingHeader: false, // Will be determined later
            hasRepeatingFooter: false, // Will be determined later
            averageLineHeight: calculateAverageLineHeight(extractedLines),
            pageHeight: Float(image.size.height)
        )
    }
    
    // MARK: - Vision Results Processing
    
    private func processVisionResults(
        _ observations: [VNRecognizedTextObservation],
        image: UIImage,
        pageNumber: Int
    ) -> [ExtractedLine] {
        
        var extractedLines: [ExtractedLine] = []
        
        // Sort observations by Y position (top to bottom)
        let sortedObservations = observations.sorted { obs1, obs2 in
            // VNRecognizedTextObservation uses normalized coordinates (0.0-1.0)
            // Y=0 is bottom in Vision coordinates, so we flip for top-to-bottom reading
            return obs1.boundingBox.origin.y > obs2.boundingBox.origin.y
        }
        
        for (index, observation) in sortedObservations.enumerated() {
            guard let candidate = observation.topCandidates(1).first else { continue }
            
            let rawText = candidate.string
            let normalizedText = normalizeOCRText(rawText)
            
            // Convert Vision's normalized coordinates to image coordinates
            let visionBox = observation.boundingBox
            let imageHeight = image.size.height
            let imageWidth = image.size.width
            
            // Convert from Vision coordinates (bottom-left origin, normalized) to image coordinates
            let boundingBox = CGRect(
                x: visionBox.origin.x * imageWidth,
                y: (1.0 - visionBox.origin.y - visionBox.height) * imageHeight, // Flip Y
                width: visionBox.width * imageWidth,
                height: visionBox.height * imageHeight
            )
            
            let indentationLevel = calculateIndentationLevel(rawText)
            let confidence = candidate.confidence
            
            let extractedLine = ExtractedLine(
                rawText: rawText,
                normalizedText: normalizedText,
                pageNumber: pageNumber,
                lineNumber: index + 1,
                boundingBox: boundingBox,
                confidence: confidence,
                estimatedFontSize: Float(boundingBox.height * 0.8), // Rough font size estimate
                indentationLevel: indentationLevel,
                yPosition: Float(boundingBox.origin.y),
                method: .visionOCR
            )
            
            extractedLines.append(extractedLine)
        }
        
        return extractedLines
    }
    
    // MARK: - Fallback Extraction
    
    private func fallbackExtraction(
        cgImage: CGImage,
        pageNumber: Int,
        customWords: OCRCustomWords
    ) async throws -> NormalizedPage {
        
        // Try fast recognition as fallback
        let fastRequest = VNRecognizeTextRequest()
        fastRequest.recognitionLevel = .fast
        fastRequest.usesLanguageCorrection = true
        
        if !customWords.allWords.isEmpty {
            fastRequest.customWords = customWords.allWords
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try requestHandler.perform([fastRequest])
        
        guard let observations = fastRequest.results, !observations.isEmpty else {
            throw ExtractionError.noTextFound
        }
        
        let extractedLines = processVisionResults(observations, image: UIImage(cgImage: cgImage)!, pageNumber: pageNumber)
        
        return NormalizedPage(
            pageNumber: pageNumber,
            lines: extractedLines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: calculateAverageLineHeight(extractedLines),
            pageHeight: Float(cgImage.height)
        )
    }
    
    // MARK: - Helper Methods
    
    private func convertPDFPageToImage(_ page: PDFPage) -> UIImage? {
        let pageSize = page.bounds(for: .mediaBox).size
        // Use higher resolution for better OCR
        let scale: CGFloat = 3.0
        let scaledSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: scaledSize))
            
            ctx.cgContext.translateBy(x: 0, y: scaledSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        
        return image
    }
    
    private func normalizeOCRText(_ text: String) -> String {
        var normalized = text
        
        // Fix common OCR errors
        normalized = normalized.replacingOccurrences(of: "|", with: "I") // Common I/| confusion
        normalized = normalized.replacingOccurrences(of: "0", with: "O") // In text contexts where 0 should be O
        normalized = normalized.replacingOccurrences(of: "5", with: "S") // In text contexts where 5 should be S
        
        // Clean up whitespace
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return normalized
    }
    
    private func calculateIndentationLevel(_ text: String) -> Int {
        var leadingSpaces = 0
        for char in text {
            if char == " " {
                leadingSpaces += 1
            } else if char == "\t" {
                leadingSpaces += 4
            } else {
                break
            }
        }
        return max(0, leadingSpaces / 4)
    }
    
    private func calculateAverageLineHeight(_ lines: [ExtractedLine]) -> Float {
        guard !lines.isEmpty else { return 16.0 }
        
        let totalHeight = lines.reduce(0) { sum, line in
            sum + Float(line.boundingBox.height)
        }
        
        return totalHeight / Float(lines.count)
    }
    
    private func identifyRepeatingElements(pages: [NormalizedPage]) -> [NormalizedPage] {
        guard pages.count > 1 else { return pages }
        
        // Similar logic to PDF extractor for consistency
        var potentialHeaders: [String] = []
        var potentialFooters: [String] = []
        
        for page in pages {
            // Check top 2 lines for headers
            if let firstLine = page.lines.first?.normalizedText, !firstLine.isEmpty {
                potentialHeaders.append(firstLine)
            }
            if page.lines.count > 1, let secondLine = page.lines[1].normalizedText, !secondLine.isEmpty {
                potentialHeaders.append(secondLine)
            }
            
            // Check bottom 2 lines for footers
            if let lastLine = page.lines.last?.normalizedText, !lastLine.isEmpty {
                potentialFooters.append(lastLine)
            }
            if page.lines.count > 1 {
                let secondLastLine = page.lines[page.lines.count - 2].normalizedText
                if !secondLastLine.isEmpty {
                    potentialFooters.append(secondLastLine)
                }
            }
        }
        
        let headerCounts = Dictionary(grouping: potentialHeaders, by: { $0 }).mapValues { $0.count }
        let footerCounts = Dictionary(grouping: potentialFooters, by: { $0 }).mapValues { $0.count }
        
        let repeatingHeader = headerCounts.first { $0.value >= pages.count / 2 }?.key
        let repeatingFooter = footerCounts.first { $0.value >= pages.count / 2 }?.key
        
        return pages.map { page in
            let hasHeader = repeatingHeader != nil && 
                           (page.lines.first?.normalizedText == repeatingHeader || 
                            (page.lines.count > 1 && page.lines[1].normalizedText == repeatingHeader))
            
            let hasFooter = repeatingFooter != nil && 
                           (page.lines.last?.normalizedText == repeatingFooter || 
                            (page.lines.count > 1 && page.lines[page.lines.count - 2].normalizedText == repeatingFooter))
            
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

// MARK: - Custom Words Provider

final class OCRCustomWordsProvider {
    
    func getCustomWords() async -> OCRCustomWords {
        // In a real implementation, these would be loaded from the user's existing jokes
        // For now, return default comedy terms
        
        return OCRCustomWords(
            jokeTitle: [], // TODO: Load from existing joke titles in the app
            venueName: [], // TODO: Load from user's venue history
            comedyTerms: OCRCustomWords.defaultComedyTerms,
            userSlang: []  // TODO: Extract from user's existing content
        )
    }
}