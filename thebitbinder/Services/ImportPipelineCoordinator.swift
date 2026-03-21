//
//  ImportPipelineCoordinator.swift
//  thebitbinder
//
//  Main coordinator for the multi-stage import pipeline
//

import Foundation
import UIKit

/// Coordinates the entire import pipeline from file input to final joke objects
final class ImportPipelineCoordinator {
    
    static let shared = ImportPipelineCoordinator()
    
    private let router = ImportRouter.shared
    private let pdfExtractor = PDFTextExtractor.shared
    private let ocrExtractor = OCRTextExtractor.shared
    private let lineNormalizer = LineNormalizer.shared
    private let blockBuilder = LayoutBlockBuilder.shared
    private let blockValidator = JokeBlockValidator.shared
    private let jokeExtractor = JokeExtractor.shared
    
    private init() {}
    
    /// Main pipeline entry point - processes a file and returns import result
    func processFile(url: URL) async throws -> ImportPipelineResult {
        let startTime = Date()
        var debugInfo: [String] = []
        
        // Stage 1: File Type Detection
        debugInfo.append("=== Stage 1: File Type Detection ===")
        let fileType = await router.detectFileType(url: url)
        let extractionMethod = router.getExtractionMethod(for: fileType)
        debugInfo.append("Detected file type: \(fileType)")
        debugInfo.append("Selected extraction method: \(extractionMethod)")
        
        // Stage 2: Text Extraction
        debugInfo.append("\n=== Stage 2: Text Extraction ===")
        let extractedPages = try await extractText(from: url, fileType: fileType, method: extractionMethod)
        debugInfo.append("Extracted \(extractedPages.count) pages")
        debugInfo.append("Total lines: \(extractedPages.flatMap(\.lines).count)")
        
        // Stage 3: Line Normalization
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
        debugInfo.append("Normalized and merged lines")
        debugInfo.append("Clean lines: \(cleanedPages.flatMap(\.lines).count)")
        
        // Stage 4: Layout Block Building
        debugInfo.append("\n=== Stage 4: Layout Block Building ===")
        let layoutBlocks = blockBuilder.buildBlocks(from: cleanedPages)
        debugInfo.append("Created \(layoutBlocks.count) layout blocks")
        for (index, block) in layoutBlocks.enumerated() {
            debugInfo.append("Block \(index + 1): \(block.blockType), \(block.lines.count) lines, \(block.text.prefix(50))...")
        }
        
        // Stage 5: Block Validation
        debugInfo.append("\n=== Stage 5: Block Validation ===")
        let validations = blockValidator.validateBlocks(layoutBlocks)
        let autoSaveCount = validations.filter(\.shouldAutoSave).count
        let reviewCount = validations.filter(\.requiresReview).count
        let rejectCount = validations.count - autoSaveCount - reviewCount
        debugInfo.append("Validation results: \(autoSaveCount) auto-save, \(reviewCount) review, \(rejectCount) reject")
        
        for (index, validation) in validations.enumerated() {
            debugInfo.append("Block \(index + 1): \(validation.result), confidence: \(validation.confidence)")
            if !validation.issues.isEmpty {
                debugInfo.append("  Issues: \(validation.issues.map(\.description).joined(separator: ", "))")
            }
        }
        
        // Stage 6: Joke Extraction
        debugInfo.append("\n=== Stage 6: Joke Extraction ===")
        var autoSavedJokes: [ImportedJoke] = []
        var reviewQueueJokes: [ImportedJoke] = []
        var rejectedBlocks: [LayoutBlock] = []
        
        for (index, validation) in validations.enumerated() {
            if let joke = jokeExtractor.extractJoke(from: validation, sourceFile: url.lastPathComponent) {
                var finalJoke = joke
                // Set the correct order in file
                finalJoke = ImportedJoke(
                    title: joke.title,
                    body: joke.body,
                    rawSourceText: joke.rawSourceText,
                    tags: joke.tags,
                    confidence: joke.confidence,
                    confidenceFactors: joke.confidenceFactors,
                    sourceMetadata: ImportSourceMetadata(
                        fileName: joke.sourceMetadata.fileName,
                        pageNumber: joke.sourceMetadata.pageNumber,
                        orderInPage: joke.sourceMetadata.orderInPage,
                        orderInFile: index,
                        boundingBox: joke.sourceMetadata.boundingBox,
                        importTimestamp: joke.sourceMetadata.importTimestamp,
                        pipelineVersion: joke.sourceMetadata.pipelineVersion
                    ),
                    validationResult: joke.validationResult,
                    extractionMethod: joke.extractionMethod
                )
                
                if finalJoke.needsReview {
                    reviewQueueJokes.append(finalJoke)
                } else {
                    autoSavedJokes.append(finalJoke)
                }
            } else {
                rejectedBlocks.append(validation.block)
            }
        }
        
        debugInfo.append("Extracted \(autoSavedJokes.count) auto-save jokes")
        debugInfo.append("Extracted \(reviewQueueJokes.count) review queue jokes")
        debugInfo.append("Rejected \(rejectedBlocks.count) blocks")
        
        // Calculate processing time and stats
        let processingTime = Date().timeIntervalSince(startTime)
        let totalLines = extractedPages.flatMap(\.lines).count
        
        let stats = PipelineStats(
            totalPagesProcessed: extractedPages.count,
            totalLinesExtracted: totalLines,
            totalBlocksCreated: layoutBlocks.count,
            autoSavedCount: autoSavedJokes.count,
            reviewQueueCount: reviewQueueJokes.count,
            rejectedCount: rejectedBlocks.count,
            extractionMethod: extractionMethod,
            processingTimeSeconds: processingTime,
            averageConfidence: calculateAverageConfidence(autoSavedJokes + reviewQueueJokes)
        )
        
        let pipelineDebugInfo = PipelineDebugInfo(
            fileTypeDetection: "File type: \(fileType), Method: \(extractionMethod)",
            extractionDetails: "Pages: \(extractedPages.count), Lines: \(totalLines)",
            blockSplittingDecisions: debugInfo.filter { $0.contains("Block") },
            validationDecisions: debugInfo.filter { $0.contains("validation") || $0.contains("Issues") },
            confidenceCalculations: validations.map { "Block: \($0.confidence), Issues: \($0.issues.count)" }
        )
        
        // Log the import operation
        DataOperationLogger.shared.logBulkOperation(
            "IMPORT",
            entityType: "Joke",
            count: autoSavedJokes.count + reviewQueueJokes.count,
            context: ModelContext() // This would be injected in real usage
        )
        
        return ImportPipelineResult(
            sourceFile: url.lastPathComponent,
            autoSavedJokes: autoSavedJokes,
            reviewQueueJokes: reviewQueueJokes,
            rejectedBlocks: rejectedBlocks,
            pipelineStats: stats,
            debugInfo: pipelineDebugInfo
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
                // Single image
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else {
                    throw ImportProcessingError.invalidImageFile
                }
                let page = try await ocrExtractor.extractFromImage(image)
                return [page]
            }
            
        case .documentText:
            return try await extractFromDocument(url: url)
            
        case .imageOCR:
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                throw ImportProcessingError.invalidImageFile
            }
            let page = try await ocrExtractor.extractFromImage(image)
            return [page]
        }
    }
    
    private func extractFromDocument(url: URL) async throws -> [NormalizedPage] {
        // Handle .doc, .docx, .rtf, .txt files
        var text: String
        
        if url.pathExtension.lowercased() == "txt" {
            text = try String(contentsOf: url)
        } else {
            // Use NSAttributedString for rich text formats
            let attributedString = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            text = attributedString.string
        }
        
        // Convert to lines and create normalized page
        let lines = text.components(separatedBy: .newlines)
        var extractedLines: [ExtractedLine] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let extractedLine = ExtractedLine(
                rawText: line,
                normalizedText: trimmed,
                pageNumber: 1,
                lineNumber: index + 1,
                boundingBox: CGRect(x: 0, y: Float(index) * 20, width: 500, height: 20), // Estimated
                confidence: 1.0,
                estimatedFontSize: 12.0,
                indentationLevel: calculateIndentationLevel(line),
                yPosition: Float(index) * 20,
                method: .documentText
            )
            
            extractedLines.append(extractedLine)
        }
        
        return [NormalizedPage(
            pageNumber: 1,
            lines: extractedLines,
            hasRepeatingHeader: false,
            hasRepeatingFooter: false,
            averageLineHeight: 20.0,
            pageHeight: Float(extractedLines.count) * 20
        )]
    }
    
    private func calculateIndentationLevel(_ line: String) -> Int {
        var spaces = 0
        for char in line {
            if char == " " {
                spaces += 1
            } else if char == "\t" {
                spaces += 4
            } else {
                break
            }
        }
        return spaces / 4
    }
    
    // MARK: - Helper Methods
    
    private func calculateAverageConfidence(_ jokes: [ImportedJoke]) -> Float {
        guard !jokes.isEmpty else { return 0.0 }
        
        let confidenceSum = jokes.reduce(0.0) { sum, joke in
            sum + joke.confidenceFactors.overallScore
        }
        
        return confidenceSum / Float(jokes.count)
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
        case .invalidImageFile:
            return "Invalid or corrupted image file"
        case .unsupportedFileType:
            return "Unsupported file type for import"
        case .extractionFailed:
            return "Failed to extract text from file"
        case .validationFailed:
            return "Content validation failed"
        }
    }
}