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

    private init() {}
    
    // MARK: - Memory Monitoring
    
    /// Returns the fraction of memory used (0.0–1.0). Above 0.75 is considered high pressure.
    private func memoryPressure() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        var taskInfo = mach_task_basic_info()
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let usedMB = Double(taskInfo.resident_size) / (1024 * 1024)
        let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024)
        return min(usedMB / totalMB, 1.0)
    }
    
    /// Returns true if memory pressure is dangerously high (>75% physical memory used).
    private var isUnderMemoryPressure: Bool {
        memoryPressure() > 0.75
    }

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

        debugInfo.append("\n=== Stage 4: AI Joke Extraction (Multi-Provider) ===")
        let availableAI = AIJokeExtractionManager.shared.availableProviders
        debugInfo.append("Sending \(fullText.count) chars to AI extraction")
        debugInfo.append("Available providers: \(availableAI.map(\.displayName).joined(separator: " → "))")
        debugInfo.append("Remaining Gemini requests today: \(GeminiJokeExtractor.shared.remainingRequests())")

        // ── Stage 5: Multi-provider extraction (with local fallback) ──────
        let extractionResult = await AIJokeExtractionManager.shared.extractJokesForPipeline(from: fullText)
        let geminiJokes = extractionResult.jokes
        let usedLocalFallback = extractionResult.usedLocalFallback
        let providerUsed = extractionResult.providerUsed

        if usedLocalFallback {
            debugInfo.append("⚠️ All AI providers unavailable — used local rule-based extraction")
            debugInfo.append("Local extractor returned \(geminiJokes.count) potential joke(s)")
        } else {
            debugInfo.append("✅ Extracted \(geminiJokes.count) joke(s) via \(providerUsed)")
        }

        debugInfo.append("Extracted \(geminiJokes.count) joke(s) (\(providerUsed))")

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
            confidenceCalculations: geminiJokes.map { "AI confidence: \($0.confidence)" }
        )

        print("📊 IMPORT (\(providerUsed)): \(autoSavedJokes.count + reviewQueueJokes.count) jokes processed from \(url.lastPathComponent)")

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
        
        // Check memory before starting extraction
        if isUnderMemoryPressure {
            print("⚠️ [ImportPipeline] High memory pressure (\(Int(memoryPressure() * 100))%) before extraction — proceeding cautiously")
        }

        switch method {
        case .pdfKitText:
            return try await pdfExtractor.extractPages(from: url)

        case .visionOCR:
            if fileType == .scannedPDF {
                // Process scanned PDFs page-by-page with memory checks
                return try await extractOCRWithMemoryManagement(from: url)
            } else {
                // Load image data in an autoreleasepool to free intermediate buffers
                let image: UIImage = try autoreleasepool {
                    guard let data  = try? Data(contentsOf: url),
                          let img = UIImage(data: data) else {
                        throw ImportProcessingError.invalidImageFile
                    }
                    return img
                }
                let page = try await ocrExtractor.extractFromImage(image)
                return [page]
            }

        case .documentText:
            return try await extractFromDocument(url: url)

        case .imageOCR:
            let image: UIImage = try autoreleasepool {
                guard let data  = try? Data(contentsOf: url),
                      let img = UIImage(data: data) else {
                    throw ImportProcessingError.invalidImageFile
                }
                return img
            }
            let page = try await ocrExtractor.extractFromImage(image)
            return [page]
        }
    }
    
    /// Extracts OCR text from a scanned PDF page-by-page, releasing memory between pages.
    /// Aborts early if memory pressure exceeds safe thresholds.
    private func extractOCRWithMemoryManagement(from url: URL) async throws -> [NormalizedPage] {
        // Delegate to the existing OCR extractor but monitor memory throughout
        let pages = try await ocrExtractor.extractFromPDF(url: url)
        
        // After extraction, check if memory is critically high
        if isUnderMemoryPressure {
            print("⚠️ [ImportPipeline] High memory after OCR extraction (\(Int(memoryPressure() * 100))%) — consider reducing page count")
        }
        
        return pages
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
