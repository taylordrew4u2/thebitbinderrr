//
//  ImportRouter.swift
//  thebitbinder
//
//  File type detection and routing for import pipeline
//

import Foundation
import PDFKit
import UIKit

/// Routes import files to appropriate extraction methods based on content analysis
final class ImportRouter {
    
    static let shared = ImportRouter()
    private init() {}
    
    /// Analyzes file and determines optimal extraction strategy
    func detectFileType(url: URL) async -> ImportFileType {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf":
            return await analyzePDFType(url: url)
        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "gif":
            return .image
        case "doc", "docx", "rtf", "txt":
            return .document
        default:
            return .unknown
        }
    }
    
    /// Determines whether PDF contains searchable text or needs OCR
    private func analyzePDFType(url: URL) async -> ImportFileType {
        guard let document = PDFDocument(url: url) else {
            return .unknown
        }
        
        let pageCount = min(document.pageCount, 3) // Sample first 3 pages max
        var totalSelectableChars = 0
        var totalPages = 0
        var pagesWithSubstantialText = 0
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            totalPages += 1
            
            let pageText = page.string ?? ""
            let cleanText = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            totalSelectableChars += cleanText.count
            
            // More sophisticated text detection
            if hasSubstantialSelectableText(cleanText) {
                pagesWithSubstantialText += 1
            }
        }
        
        // Decision logic:
        // - If most pages have substantial selectable text, treat as text PDF
        // - If pages have some text but it's sparse/low quality, treat as scanned
        let textPageRatio = totalPages > 0 ? Float(pagesWithSubstantialText) / Float(totalPages) : 0.0
        let avgCharsPerPage = totalPages > 0 ? totalSelectableChars / totalPages : 0
        
        if textPageRatio >= 0.7 && avgCharsPerPage >= 100 {
            return .textPDF
        } else {
            return .scannedPDF
        }
    }
    
    /// Determines if extracted text is substantial enough to use
    private func hasSubstantialSelectableText(_ text: String) -> Bool {
        // Remove common PDF artifacts and noise
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Must have minimum character count
        guard cleaned.count >= 50 else { return false }
        
        // Calculate meaningful content ratio
        let letters = cleaned.filter { $0.isLetter }
        let letterRatio = Float(letters.count) / Float(cleaned.count)
        
        // Must have reasonable letter-to-total ratio (avoid PDFs with mostly symbols/spacing)
        guard letterRatio >= 0.4 else { return false }
        
        // Check for complete words (not just character soup)
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        let substantialWords = words.filter { $0.count >= 2 }
        let wordRatio = Float(substantialWords.count) / Float(words.count)
        
        // Must have reasonable proportion of substantial words
        return wordRatio >= 0.5
    }
    
    /// Gets optimal extraction method for file type
    func getExtractionMethod(for fileType: ImportFileType) -> ExtractionMethod {
        switch fileType {
        case .textPDF:
            return .pdfKitText
        case .scannedPDF, .image:
            return .visionOCR
        case .document:
            return .documentText
        case .unknown:
            return .visionOCR // Fallback to OCR for unknown types
        }
    }
    
    /// Validates that file can be processed
    func canProcess(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let supportedExtensions = [
            "pdf", "jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp", "gif",
            "doc", "docx", "rtf", "txt"
        ]
        return supportedExtensions.contains(ext)
    }
    
    /// Gets estimated complexity for processing time estimation
    func estimateProcessingComplexity(url: URL, fileType: ImportFileType) async -> ProcessingComplexity {
        switch fileType {
        case .textPDF:
            // Quick for PDFs with selectable text
            return .low
        case .scannedPDF:
            // More complex due to OCR
            guard let document = PDFDocument(url: url) else { return .medium }
            let pageCount = document.pageCount
            if pageCount <= 2 { return .medium }
            else if pageCount <= 5 { return .high }
            else { return .veryHigh }
        case .image:
            // Single image OCR is medium complexity
            return .medium
        case .document:
            // Simple text extraction
            return .low
        case .unknown:
            return .high
        }
    }
}

enum ProcessingComplexity {
    case low        // < 1 second
    case medium     // 1-3 seconds
    case high       // 3-10 seconds
    case veryHigh   // > 10 seconds
    
    var estimatedSeconds: TimeInterval {
        switch self {
        case .low: return 0.5
        case .medium: return 2.0
        case .high: return 6.0
        case .veryHigh: return 15.0
        }
    }
}