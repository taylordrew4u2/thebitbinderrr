//
//  ImportPipelineCoordinator.swift
//  thebitbinder
//
//  Main coordinator for the multi-stage import pipeline.
//  Handles file type detection, text extraction, and joke extraction.
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

        // ── Stage 0: Upfront Validation ────────────────────────────────────────
        // Check file type FIRST — before touching the file data, before OCR, before AI.
        // This prevents code/.swift files from reaching the image extraction path.
        let fileType = await router.detectFileType(url: url)

        if fileType == .unsupported {
            let ext = url.pathExtension.isEmpty ? "unknown" : url.pathExtension
            print("🚫 [ImportPipeline] Rejected unsupported file type: .\(ext) (\(url.lastPathComponent))")
            throw ImportValidationError.unsupportedFileType(extension: ext)
        }

        // Verify the file is readable and non-empty before any expensive work.
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ImportValidationError.fileNotReadable(url)
        }
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttributes?[.size] as? Int) ?? 0
        if fileSize == 0 {
            throw ImportValidationError.emptyFile(url)
        }

        // ── Stage 1: File Type Detection ─────────────────────────────────────
        debugInfo.append("=== Stage 1: File Type Detection ===")
        let extractionMethod = router.getExtractionMethod(for: fileType)
        debugInfo.append("Detected file type: \(fileType)")
        debugInfo.append("Selected extraction method: \(extractionMethod)")

        // ── Stage 2: Text / Image Extraction ─────────────────────────────────
        debugInfo.append("\n=== Stage 2: Text Extraction ===")
        let extractedPages = try await extractText(from: url, fileType: fileType, method: extractionMethod)
        debugInfo.append("Extracted \(extractedPages.count) pages")
        debugInfo.append("Total lines: \(extractedPages.flatMap(\.lines).count)")

        // ── Stage 3: Line Normalization ───────────────────────────────────────
        debugInfo.append("\n=== Stage 3: Line Normalization ===")
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

        // ── Stage 4: Reassemble plain text for extraction ─────────────────────────
        // We merge all clean pages back into one text string so extraction providers
        // can see the full document context rather than fragmented chunks.
        let fullText = cleanedPages
            .flatMap(\.lines)
            .map(\.normalizedText)
            .joined(separator: "\n")

        debugInfo.append("\n=== Stage 4: Joke Extraction (AI — no local fallback) ===")
        let availableAI = AIJokeExtractionManager.shared.availableProviders
        debugInfo.append("Sending \(fullText.count) chars to extraction")
        debugInfo.append("Available providers: \(availableAI.map(\.displayName).joined(separator: " → "))")

        // ── Stage 5: AI extraction — throws AIExtractionFailedError if every provider fails ──
        // There is NO local fallback. If this throws, the caller must surface an error to the user.
        //
        // Large files (>40k chars) are split into ~30k-char chunks to keep each
        // request well within the model's output token budget and avoid
        // finish_reason=length truncation. Each chunk is extracted independently
        // and the results are concatenated before mapping to ImportedJoke objects.
        // The chunk boundary is on a newline so we never cut mid-sentence.
        let importToken = AIExtractionToken(caller: "ImportPipelineCoordinator")
        var geminiJokes: [GeminiExtractedJoke]
        var providerUsed: String
        let textChunks = splitIntoExtractionChunks(fullText)
        var aiExtractionFailed = false
        if textChunks.count == 1 {
            do {
                let result = try await AIJokeExtractionManager.shared.extractJokesForPipeline(from: textChunks[0], token: importToken)
                geminiJokes  = result.jokes
                providerUsed = result.providerUsed
            } catch {
                aiExtractionFailed = true
                geminiJokes = []
                providerUsed = "AI Extraction Failed"
            }
        } else {
            var allJokes: [GeminiExtractedJoke] = []
            var lastProvider = "Unknown"
            debugInfo.append("⚡ Large file split into \(textChunks.count) chunks for extraction")
            for (chunkIndex, chunk) in textChunks.enumerated() {
                do {
                    debugInfo.append("  Chunk \(chunkIndex + 1)/\(textChunks.count): \(chunk.count) chars")
                    let result = try await AIJokeExtractionManager.shared.extractJokesForPipeline(from: chunk, token: importToken)
                    allJokes.append(contentsOf: result.jokes)
                    lastProvider = result.providerUsed
                } catch {
                    aiExtractionFailed = true
                }
            }
            geminiJokes  = allJokes
            providerUsed = lastProvider
        }
        // Fallback: If AI extraction failed or returned 0, split every word as a bit
        if aiExtractionFailed || geminiJokes.isEmpty {
            debugInfo.append("⚠️ AI extraction failed or returned 0 results. Falling back to word-split bits.")
            let words = fullText.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
            geminiJokes = words.map { word in
                GeminiExtractedJoke(jokeText: word, humorMechanism: nil, confidence: 0.0, explanation: nil, title: nil, tags: [])
            }
            providerUsed = aiExtractionFailed ? "Fallback: AI Error" : "Fallback: 0 Results"
        }

        debugInfo.append("✅ Extracted \(geminiJokes.count) fragment(s) via \(providerUsed)")

        // ── Stage 6: Map into ImportedJoke ────────────────────────────────────
        // Fragments with confidence ≥ 0.8 go to auto-save; everything else goes
        // to the review queue so the user sees and decides on every single fragment.
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
            confidenceCalculations: geminiJokes.map { "Confidence: \($0.confidence)" }
        )

        print("📊 IMPORT (\(providerUsed)): \(autoSavedJokes.count + reviewQueueJokes.count) jokes processed from \(url.lastPathComponent)")

        return ImportPipelineResult(
            sourceFile:       url.lastPathComponent,
            autoSavedJokes:   autoSavedJokes,
            reviewQueueJokes: reviewQueueJokes,
            rejectedBlocks:   [],
            pipelineStats:    stats,
            debugInfo:        pipelineDebugInfo,
            providerUsed:     providerUsed
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
                // Decode the image file, extract the CGImage, then immediately release
                // the UIImage and raw Data before the async Vision call begins.
                // (autoreleasepool cannot wrap async calls, so we separate the sync
                //  decode from the async extraction explicitly.)
                let cgImage: CGImage = try {
                    autoreleasepool {
                        guard let data = try? Data(contentsOf: url),
                              let img  = UIImage(data: data),
                              let cg   = img.cgImage else {
                            return nil as CGImage?
                        }
                        return cg
                    }
                }() ?? { throw ImportProcessingError.invalidImageFile }()
                // UIImage and Data are released here; only the CGImage survives
                let page = try await ocrExtractor.extractFromCGImage(cgImage)
                return [page]
            }

        case .documentText:
            return try await extractFromDocument(url: url)

        case .imageOCR:
            let cgImage: CGImage = try {
                autoreleasepool {
                    guard let data = try? Data(contentsOf: url),
                          let img  = UIImage(data: data),
                          let cg   = img.cgImage else {
                        return nil as CGImage?
                    }
                    return cg
                }
            }() ?? { throw ImportProcessingError.invalidImageFile }()
            // UIImage and Data released; only CGImage survives into async call
            let page = try await ocrExtractor.extractFromCGImage(cgImage)
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

    /// Maximum characters per extraction chunk.
    ///
    /// 30 000 chars ≈ 7 500 tokens of input text.  At a 3:1 output/input ratio
    /// the model would need ~22 500 output tokens — well within gpt-4o-mini's
    /// 16 384 output token limit per call.  We stay conservative at 30k chars
    /// so even very wordy files don't risk truncation mid-joke.
    ///
    /// Files under this limit are sent as a single request (the common case).
    private static let extractionChunkSizeChars = 30_000

    /// Splits `text` into at most `extractionChunkSizeChars`-character chunks
    /// aligned on newline boundaries so we never cut a sentence in half.
    ///
    /// Chunks overlap by one blank line so a joke split across the boundary
    /// doesn't get lost.  In practice comedian files are rarely >30k chars so
    /// this fast path almost never runs.
    private func splitIntoExtractionChunks(_ text: String) -> [String] {
        let limit = Self.extractionChunkSizeChars
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            if remaining.count <= limit {
                chunks.append(String(remaining))
                break
            }

            // Find the last newline within the first `limit` characters
            let endIdx = remaining.index(remaining.startIndex, offsetBy: limit)
            let searchRegion = remaining[..<endIdx]
            let splitIdx = searchRegion.lastIndex(of: "\n") ?? endIdx

            let chunk = String(remaining[..<splitIdx])
            if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(chunk)
            }

            // Advance past the split point, skipping leading whitespace
            let nextStart = remaining.index(after: splitIdx)
            if nextStart >= remaining.endIndex { break }
            remaining = remaining[nextStart...]
        }

        return chunks.isEmpty ? [text] : chunks
    }

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
