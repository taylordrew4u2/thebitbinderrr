//
//  ImportPipelineCoordinator.swift
//  thebitbinder
//
//  Main coordinator for the multi-stage import pipeline.
//  Stage 6 (joke extraction) now uses GeminiJokeExtractor.
//

import Foundation
import UIKit
import SwiftData

/// Coordinates the entire import pipeline from file input to final joke objects.
final class ImportPipelineCoordinator {

    static let shared = ImportPipelineCoordinator()

    private let router          = ImportRouter.shared
    private let pdfExtractor    = PDFTextExtractor.shared
    private let ocrExtractor    = OCRTextExtractor.shared
    private let lineNormalizer  = LineNormalizer.shared
    private let blockBuilder    = LayoutBlockBuilder.shared

    private init() {}

    // MARK: - Main Pipeline Entry Point

    /// Processes a file and returns an `ImportPipelineResult`.
    func processFile(url: URL) async throws -> ImportPipelineResult {
        let startTime = Date()
        var debugInfo: [String] = []

        // ── Stage 1: File Type Detection ─────────────────────────────────────
        debugInfo.append("=== Stage 1: File Type Detection ===")
        let fileType        = await router.detectFileType(url: url)
        let extractionMethod = router.getExtractionMethod(for: fileType)
        debugInfo.append("Detected file type: \(fileType)")
        debugInfo.append("Selected extraction method: \(extractionMethod)")

        // ── Stage 2: Text / Image Extraction ─────────────────────────────────
        debugInfo.append("\n=== Stage 2: Text Extraction ===")
        let extractedPages = try await extractText(from: url, fileType: fileType, method: extractionMethod)
        debugInfo.append("Extracted \(extractedPages.count) pages")
        debugInfo.append("Total lines: \(extractedPages.flatMap(\.lines).count)")

        // ── Stage 3: Line Normalisation ───────────────────────────────────────
        debugInfo.append("\n=== Stage 3: Line Normalisation ===")
        let normalizedPages = lineNormalizer.normalizePages(extractedPages)
        let cleanedPages = normalizedPages.map { page in
            let mergedLines = lineNormalizer.mergeFragmentedLines(page.lines)
            return NormalizedPage(
                pageNumber: page.pageNumber,
                lines: mergedLines,
                hasRepeatingHeader: page.hasRepeatingHeader,
                hasRepeatingFooter: page.hasRepeatingFooter,
                averageLineHeight: page.averageLineHeight,
                pageHeight: page.pageHeight
            )
        }
        debugInfo.append("Clean lines: \(cleanedPages.flatMap(\.lines).count)")

        // ── Stage 4: Reassemble plain text for Gemini ─────────────────────────
        // We merge all clean pages back into one text string so Gemini sees the
        // full document context rather than fragmented chunks.
        let fullText = cleanedPages
            .flatMap(\.lines)
            .map(\.normalizedText)
            .joined(separator: "\n")

        debugInfo.append("\n=== Stage 4: Gemini Joke Extraction ===")
        debugInfo.append("Sending \(fullText.count) chars to Gemini 2.0 Flash")
        debugInfo.append("Remaining Gemini requests today: \(GeminiJokeExtractor.shared.remainingRequests())")

        // ── Stage 5: Gemini extraction ────────────────────────────────────────
        let geminiJokes: [GeminiExtractedJoke]
        do {
            geminiJokes = try await GeminiJokeExtractor.shared.extract(from: fullText)
        } catch let rateLimitError as GeminiRateLimitError {
            debugInfo.append("⚠️ Gemini error: \(rateLimitError.localizedDescription ?? "unknown")")
            throw rateLimitError
        }

        debugInfo.append("Gemini returned \(geminiJokes.count) joke(s)")

        // ── Stage 6: Map into ImportedJoke ────────────────────────────────────
        let importTimestamp = Date()
        var autoSavedJokes:   [ImportedJoke] = []
        var reviewQueueJokes: [ImportedJoke] = []

        for (index, geminiJoke) in geminiJokes.enumerated() {
            let imported = geminiJoke.toImportedJoke(
                sourceFile: url.lastPathComponent,
                pageNumber: 1,
                orderInFile: index,
                importTimestamp: importTimestamp
            )
            if imported.needsReview {
                reviewQueueJokes.append(imported)
            } else {
                autoSavedJokes.append(imported)
            }
        }

        debugInfo.append("Auto-save: \(autoSavedJokes.count), Review queue: \(reviewQueueJokes.count)")

        // ── Stats ─────────────────────────────────────────────────────────────
        let processingTime = Date().timeIntervalSince(startTime)
        let totalLines     = extractedPages.flatMap(\.lines).count

        let stats = PipelineStats(
            totalPagesProcessed:  extractedPages.count,
            totalLinesExtracted:  totalLines,
            totalBlocksCreated:   geminiJokes.count,
            autoSavedCount:       autoSavedJokes.count,
            reviewQueueCount:     reviewQueueJokes.count,
            rejectedCount:        0,
            extractionMethod:     extractionMethod,
            processingTimeSeconds: processingTime,
            averageConfidence:    calculateAverageConfidence(autoSavedJokes + reviewQueueJokes)
        )

        let pipelineDebugInfo = PipelineDebugInfo(
            fileTypeDetection:      "File type: \(fileType), Method: \(extractionMethod)",
            extractionDetails:      "Pages: \(extractedPages.count), Lines: \(totalLines)",
            blockSplittingDecisions: [],
            validationDecisions:    [],
            confidenceCalculations: geminiJokes.map { "Gemini confidence: \($0.confidence)" }
        )

        print("📊 IMPORT (Gemini): \(autoSavedJokes.count + reviewQueueJokes.count) jokes processed from \(url.lastPathComponent)")

        return ImportPipelineResult(
            sourceFile:       url.lastPathComponent,
            autoSavedJokes:   autoSavedJokes,
            reviewQueueJokes: reviewQueueJokes,
            rejectedBlocks:   [],          // Gemini discards non-jokes; no raw blocks to track
            pipelineStats:    stats,
            debugInfo:        pipelineDebugInfo
        )
    }

    // MARK: - Text Extraction Stage

    private func extractText(
        from url: URL,
        fileType: ImportFileType,
        method: ExtractionMethod
    ) async throws -> [NormalizedPage] {

        switch method {
        case .pdfKitText:
            return try await pdfExtractor.extractPages(from: url)

        case .visionOCR:
            if fileType == .scannedPDF {
                return try await ocrExtractor.extractFromPDF(url: url)
            } else {
                guard let data  = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else {
                    throw ImportProcessingError.invalidImageFile
                }
                let page = try await ocrExtractor.extractFromImage(image)
                return [page]
            }

        case .documentText:
            return try await extractFromDocument(url: url)

        case .imageOCR:
            guard let data  = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                throw ImportProcessingError.invalidImageFile
            }
            let page = try await ocrExtractor.extractFromImage(image)
            return [page]
        }
    }

    private func extractFromDocument(url: URL) async throws -> [NormalizedPage] {
        var text: String

        if url.pathExtension.lowercased() == "txt" {
            text = try String(contentsOf: url)
        } else {
            let attributedString = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            text = attributedString.string
        }

        // Smart content-aware splitting so downstream block-builder still works
        let chunks = SmartTextSplitter.split(text)

        var pages: [NormalizedPage] = []
        for (chunkIndex, chunk) in chunks.enumerated() {
            let chunkLines = chunk.components(separatedBy: .newlines)
            var extractedLines: [ExtractedLine] = []

            for (lineIndex, line) in chunkLines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                extractedLines.append(ExtractedLine(
                    rawText: line,
                    normalizedText: trimmed,
                    pageNumber: chunkIndex + 1,
                    lineNumber: lineIndex + 1,
                    boundingBox: CGRect(x: 0, y: CGFloat(lineIndex) * 20, width: 500, height: 20),
                    confidence: 1.0,
                    estimatedFontSize: 12.0,
                    indentationLevel: calculateIndentationLevel(line),
                    yPosition: Float(lineIndex) * 20,
                    method: .documentText
                ))
            }

            guard !extractedLines.isEmpty else { continue }
            pages.append(NormalizedPage(
                pageNumber: chunkIndex + 1,
                lines: extractedLines,
                hasRepeatingHeader: false,
                hasRepeatingFooter: false,
                averageLineHeight: 20.0,
                pageHeight: Float(extractedLines.count) * 20
            ))
        }

        // Fallback: single page with all lines
        if pages.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            var extractedLines: [ExtractedLine] = []
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                extractedLines.append(ExtractedLine(
                    rawText: line, normalizedText: trimmed,
                    pageNumber: 1, lineNumber: index + 1,
                    boundingBox: CGRect(x: 0, y: CGFloat(index) * 20, width: 500, height: 20),
                    confidence: 1.0, estimatedFontSize: 12.0,
                    indentationLevel: calculateIndentationLevel(line),
                    yPosition: Float(index) * 20, method: .documentText
                ))
            }
            pages.append(NormalizedPage(
                pageNumber: 1, lines: extractedLines,
                hasRepeatingHeader: false, hasRepeatingFooter: false,
                averageLineHeight: 20.0, pageHeight: Float(extractedLines.count) * 20
            ))
        }

        return pages
    }

    private func calculateIndentationLevel(_ line: String) -> Int {
        var spaces = 0
        for char in line {
            if char == " " { spaces += 1 }
            else if char == "\t" { spaces += 4 }
            else { break }
        }
        return spaces / 4
    }

    // MARK: - Helpers

    private func calculateAverageConfidence(_ jokes: [ImportedJoke]) -> Float {
        guard !jokes.isEmpty else { return 0.0 }
        return jokes.reduce(0.0) { $0 + $1.confidenceFactors.overallScore } / Float(jokes.count)
    }
}

// MARK: - Error Types

enum ImportProcessingError: Error, LocalizedError {
    case invalidImageFile
    case unsupportedFileType
    case extractionFailed
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageFile:   return "Invalid or corrupted image file"
        case .unsupportedFileType: return "Unsupported file type for import"
        case .extractionFailed:   return "Failed to extract text from file"
        case .validationFailed:   return "Content validation failed"
        }
    }
}
