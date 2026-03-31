//
//  ImportRouter.swift
//  thebitbinder
//
//  File type detection and routing for import pipeline.
//  Uses a strict allow-list: anything not explicitly supported is rejected
//  before any expensive processing or AI extraction begins.
//

import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// Routes import files to appropriate extraction methods based on content analysis.
final class ImportRouter {

    static let shared = ImportRouter()
    private init() {}

    // MARK: - Allow / Block lists

    /// Extensions we actively support and know how to process.
    private static let supportedExtensions: Set<String> = [
        // Images
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp",
        // PDFs
        "pdf",
        // Plain text / markup
        "txt", "text", "md", "markdown",
        // Rich text / office (text extraction only)
        "rtf", "rtfd", "doc", "docx"
    ]

    /// Extensions we recognize but explicitly refuse to import as jokes.
    /// These would previously fall through to visionOCR and fail with "Invalid image file".
    private static let rejectedExtensions: Set<String> = [
        // Source code
        "swift", "m", "mm", "h", "c", "cpp", "cc", "cs", "java", "kt", "py",
        "rb", "go", "rs", "ts", "js", "jsx", "tsx", "php", "sh", "bash", "zsh",
        // Data / config
        "json", "xml", "yaml", "yml", "plist", "toml", "ini", "cfg", "env",
        // Web
        "html", "htm", "css", "scss", "less",
        // Build / project
        "pbxproj", "xcworkspace", "xcodeproj", "gradle", "podspec", "lock",
        // Binaries / archives
        "zip", "tar", "gz", "rar", "7z", "dmg", "pkg", "ipa", "apk",
        "exe", "dll", "so", "dylib", "a", "o",
        // Media
        "mp3", "mp4", "mov", "avi", "mkv", "wav", "aac", "m4a", "m4v",
        // Database / spreadsheet
        "sqlite", "db", "csv", "xls", "xlsx", "numbers",
        // Other
        "entitlements", "ckdb", "log", "tmp", "cache"
    ]

    // MARK: - Public API

    /// Determines the file type. Returns `.unsupported` immediately for any
    /// extension on the reject list so no expensive work is started.
    func detectFileType(url: URL) async -> ImportFileType {
        let ext = url.pathExtension.lowercased()

        // Hard reject — do this first, before touching the file at all.
        if Self.rejectedExtensions.contains(ext) {
            return .unsupported
        }

        switch ext {
        case "pdf":
            return await analyzePDFType(url: url)

        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp":
            return .image

        case "txt", "text", "md", "markdown", "rtf", "rtfd", "doc", "docx":
            return .document

        default:
            // Extension not in supported list either — treat as unknown (may attempt OCR).
            // Unknown is distinct from unsupported: unknown we'll try; unsupported we won't.
            if Self.supportedExtensions.contains(ext) {
                return .document // catch-all for any newly-added text types
            }
            return .unknown
        }
    }

    /// Returns the extraction method for a given file type.
    /// `.unsupported` never maps to any extraction method — callers must
    /// check for this case and reject the file before calling this.
    func getExtractionMethod(for fileType: ImportFileType) -> ExtractionMethod {
        switch fileType {
        case .textPDF:       return .pdfKitText
        case .scannedPDF:    return .visionOCR
        case .image:         return .visionOCR
        case .document:      return .documentText
        case .unknown:       return .visionOCR   // last-resort attempt
        case .unsupported:   return .documentText // never reached — coordinator rejects first
        }
    }

    /// Returns true only for file types we actively support.
    func canProcess(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return Self.supportedExtensions.contains(ext)
    }

    // MARK: - PDF Analysis

    /// Determines whether a PDF contains searchable text or needs OCR.
    private func analyzePDFType(url: URL) async -> ImportFileType {
        guard let document = PDFDocument(url: url) else { return .unknown }

        let pageCount = min(document.pageCount, 3)
        var totalSelectableChars = 0
        var totalPages = 0
        var pagesWithSubstantialText = 0

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            totalPages += 1
            let pageText = page.string ?? ""
            let cleanText = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            totalSelectableChars += cleanText.count
            if hasSubstantialSelectableText(cleanText) { pagesWithSubstantialText += 1 }
        }

        let textPageRatio   = totalPages > 0 ? Float(pagesWithSubstantialText) / Float(totalPages) : 0
        let avgCharsPerPage = totalPages > 0 ? totalSelectableChars / totalPages : 0

        return (textPageRatio >= 0.7 && avgCharsPerPage >= 100) ? .textPDF : .scannedPDF
    }

    private func hasSubstantialSelectableText(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 50 else { return false }
        let letters     = cleaned.filter { $0.isLetter }
        let letterRatio = Float(letters.count) / Float(cleaned.count)
        guard letterRatio >= 0.4 else { return false }
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        let substantialWords = words.filter { $0.count >= 2 }
        return Float(substantialWords.count) / Float(max(words.count, 1)) >= 0.5
    }

    // MARK: - Complexity Estimation

    func estimateProcessingComplexity(url: URL, fileType: ImportFileType) async -> ProcessingComplexity {
        switch fileType {
        case .textPDF:    return .low
        case .document:   return .low
        case .image:      return .medium
        case .unsupported: return .low
        case .unknown:    return .high
        case .scannedPDF:
            guard let document = PDFDocument(url: url) else { return .medium }
            switch document.pageCount {
            case ...2:  return .medium
            case 3...5: return .high
            default:    return .veryHigh
            }
        }
    }
}

// MARK: - Import Validation Error

/// Thrown when a file is rejected before any extraction begins.
enum ImportValidationError: LocalizedError {
    case unsupportedFileType(extension: String)
    case fileNotReadable(URL)
    case emptyFile(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "'\(ext)' files cannot be imported. Supported formats: PDF, images (JPG, PNG, HEIC), and text files (TXT, RTF, DOC, DOCX, MD)."
        case .fileNotReadable(let url):
            return "'\(url.lastPathComponent)' could not be read. The file may be damaged or inaccessible."
        case .emptyFile(let url):
            return "'\(url.lastPathComponent)' appears to be empty."
        }
    }
}

enum ProcessingComplexity {
    case low, medium, high, veryHigh
    var estimatedSeconds: TimeInterval {
        switch self { case .low: return 0.5; case .medium: return 2; case .high: return 6; case .veryHigh: return 15 }
    }
}
