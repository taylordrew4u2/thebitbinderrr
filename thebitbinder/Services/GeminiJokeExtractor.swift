//
//  GeminiJokeExtractor.swift
//  thebitbinder
//
//  Joke extraction powered by Google Gemini 2.0 Flash.
//  – Supports text AND image (UIImage) input
//  – Enforces a 1,000 req/day free-tier cap via UserDefaults
//  – Returns structured [GeminiExtractedJoke] results that map into
//    the existing ImportedJoke / ImportPipelineResult pipeline
//

import Foundation
import UIKit
import GoogleGenerativeAI   // GoogleGenerativeAI Swift SDK (SPM)

// MARK: - Public Model

/// A single joke extracted by Gemini.
struct GeminiExtractedJoke: Codable {
    /// The full joke text (setup + punchline, or single-line joke).
    let jokeText: String
    /// Detected humor mechanism, e.g. "pun", "wordplay", "subversion", "observational".
    let humorMechanism: String?
    /// 0.0 – 1.0; Gemini's own confidence that this block is a joke.
    let confidence: Double
    /// Short natural-language explanation of why Gemini thinks this is funny.
    let explanation: String?
    /// Optional short title / headline for the joke.
    let title: String?
    /// Thematic topic tags, e.g. ["relationships", "work"].
    let tags: [String]
}

// MARK: - Rate-Limit Error

enum GeminiRateLimitError: LocalizedError {
    case dailyLimitReached(used: Int, limit: Int)
    case apiError(String)
    case noJokesFound
    case keyNotConfigured

    var errorDescription: String? {
        switch self {
        case .dailyLimitReached(let used, let limit):
            return "Daily Gemini request limit reached (\(used)/\(limit)). Try again tomorrow."
        case .apiError(let msg):
            return "Gemini API error: \(msg)"
        case .noJokesFound:
            return "Gemini found no jokes in the provided content."
        case .keyNotConfigured:
            return "Gemini API key is not configured. Add your key to Secrets.plist under 'GEMINI_API_KEY'."
        }
    }
}

// MARK: - Rate-Limit Tracker (UserDefaults)

private struct DailyRequestTracker {
    private static let countKey  = "gemini_daily_request_count"
    private static let dateKey   = "gemini_last_request_date"
    static let dailyLimit        = 1_000

    static func canMakeRequest() -> Bool {
        resetIfNewDay()
        return currentCount() < dailyLimit
    }

    /// Increments the counter and returns the new value.
    @discardableResult
    static func increment() -> Int {
        resetIfNewDay()
        let newCount = currentCount() + 1
        UserDefaults.standard.set(newCount, forKey: countKey)
        return newCount
    }

    static func currentCount() -> Int {
        UserDefaults.standard.integer(forKey: countKey)
    }

    // MARK: private

    private static func resetIfNewDay() {
        let defaults = UserDefaults.standard
        let todayString = dayString(from: Date())
        let storedString = defaults.string(forKey: dateKey) ?? ""
        if storedString != todayString {
            defaults.set(0, forKey: countKey)
            defaults.set(todayString, forKey: dateKey)
        }
    }

    private static func dayString(from date: Date) -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

// MARK: - API Key Helper

private enum GeminiKeyLoader {
    static func loadKey() -> String? {
        // 1. Try Secrets.plist in the main bundle
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict["GEMINI_API_KEY"] as? String,
           !key.isEmpty, key != "AIzaSyBotdXSEvAUh8xb4-Qogar6EshuAaQD-C8" {
            return key
        }
        // 2. Fallback: environment variable (CI / local dev)
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
           !key.isEmpty {
            return key
        }
        return nil
    }
}

// MARK: - Main Actor

/// Thread-safe joke extractor powered by Gemini 2.0 Flash.
actor GeminiJokeExtractor {

    // MARK: Singleton

    static let shared = GeminiJokeExtractor()
    private init() {}

    // MARK: - Text Extraction

    /// Extract jokes from a plain-text string (e.g. from a .txt/.rtf/.docx file).
    /// - Parameter text: Raw text content to analyse.
    /// - Returns: Array of extracted jokes (may be empty if none found).
    /// - Throws: `GeminiRateLimitError` or a Gemini SDK error.
    func extract(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = GeminiKeyLoader.loadKey() else {
            throw GeminiRateLimitError.keyNotConfigured
        }
        guard DailyRequestTracker.canMakeRequest() else {
            throw GeminiRateLimitError.dailyLimitReached(
                used: DailyRequestTracker.currentCount(),
                limit: DailyRequestTracker.dailyLimit
            )
        }

        let model = GenerativeModel(name: "gemini-2.0-flash", apiKey: apiKey)
        let prompt = buildTextPrompt(for: text)

        DailyRequestTracker.increment()

        let response = try await model.generateContent(prompt)
        return try parseJokes(from: response)
    }

    // MARK: - Image Extraction

    /// Extract jokes from a UIImage (scanned pages, photos of notebooks, etc.).
    /// - Parameter image: The image to analyse.
    /// - Returns: Array of extracted jokes (may be empty if none found).
    /// - Throws: `GeminiRateLimitError` or a Gemini SDK error.
    func extract(from image: UIImage) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = GeminiKeyLoader.loadKey() else {
            throw GeminiRateLimitError.keyNotConfigured
        }
        guard DailyRequestTracker.canMakeRequest() else {
            throw GeminiRateLimitError.dailyLimitReached(
                used: DailyRequestTracker.currentCount(),
                limit: DailyRequestTracker.dailyLimit
            )
        }

        let model = GenerativeModel(name: "gemini-2.0-flash", apiKey: apiKey)
        let imagePart = ModelContent.Part.jpeg(image.jpegData(compressionQuality: 0.85) ?? Data())
        let textPart  = ModelContent.Part.text(imagePrompt)

        DailyRequestTracker.increment()

        let response = try await model.generateContent([ModelContent(parts: [imagePart, textPart])])
        return try parseJokes(from: response)
    }

    // MARK: - Request Count (public read-only)

    /// Number of Gemini requests made today.
    nonisolated func todayRequestCount() -> Int {
        DailyRequestTracker.currentCount()
    }

    /// Remaining requests for today.
    nonisolated func remainingRequests() -> Int {
        max(0, DailyRequestTracker.dailyLimit - DailyRequestTracker.currentCount())
    }

    // MARK: - Prompt Construction

    private func buildTextPrompt(for text: String) -> String {
        // Truncate very long inputs so we stay within token limits
        let maxChars = 12_000
        let truncated = text.count > maxChars
            ? String(text.prefix(maxChars)) + "\n...[content truncated]"
            : text

        return """
        You are a comedy writing assistant. Analyse the text below and extract every stand-up joke, \
        comedic bit, or humorous passage it contains.

        Return ONLY a valid JSON array (no markdown, no extra text). Each element must match:
        {
          "jokeText":        "<full joke text, setup + punchline>",
          "humorMechanism":  "<pun | wordplay | subversion | observational | self-deprecating | story | one-liner | other | null>",
          "confidence":      <0.0–1.0>,
          "explanation":     "<one sentence on why this is funny, or null>",
          "title":           "<short title if obvious, or null>",
          "tags":            ["<tag1>", "<tag2>"]
        }

        If no jokes are found, return an empty array: []

        --- TEXT ---
        \(truncated)
        """
    }

    private var imagePrompt: String {
        """
        You are a comedy writing assistant. Look at this image (which may be a scanned page, \
        photo of notes, or typed document) and extract every stand-up joke, comedic bit, or \
        humorous passage visible.

        Return ONLY a valid JSON array (no markdown, no extra text). Each element must match:
        {
          "jokeText":        "<full joke text, setup + punchline>",
          "humorMechanism":  "<pun | wordplay | subversion | observational | self-deprecating | story | one-liner | other | null>",
          "confidence":      <0.0–1.0>,
          "explanation":     "<one sentence on why this is funny, or null>",
          "title":           "<short title if obvious, or null>",
          "tags":            ["<tag1>", "<tag2>"]
        }

        If no jokes are found, return an empty array: []
        """
    }

    // MARK: - Response Parsing

    private func parseJokes(from response: GenerateContentResponse) throws -> [GeminiExtractedJoke] {
        // Extract the raw text from the response
        guard let raw = response.text else {
            return []
        }

        // Strip any markdown fences Gemini might wrap around the JSON
        var jsonString = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            // Remove ```json ... ``` wrapper
            let lines = jsonString.components(separatedBy: .newlines)
            let inner = lines.dropFirst().dropLast()
            jsonString = inner.joined(separator: "\n")
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw GeminiRateLimitError.apiError("Response is not valid UTF-8")
        }

        do {
            let jokes = try JSONDecoder().decode([GeminiExtractedJoke].self, from: data)
            return jokes
        } catch {
            throw GeminiRateLimitError.apiError("Failed to parse Gemini response JSON: \(error.localizedDescription). Raw: \(jsonString.prefix(300))")
        }
    }
}

// MARK: - Convenience: Convert to ImportedJoke

extension GeminiExtractedJoke {
    /// Maps a Gemini result into the existing pipeline's `ImportedJoke` model.
    func toImportedJoke(
        sourceFile: String,
        pageNumber: Int = 1,
        orderInFile: Int = 0,
        importTimestamp: Date = Date()
    ) -> ImportedJoke {
        let importConfidence: ImportConfidence
        switch confidence {
        case 0.8...: importConfidence = .high
        case 0.5...: importConfidence = .medium
        default:     importConfidence = .low
        }

        let confidenceFactors = ConfidenceFactors(
            extractionQuality: Float(confidence),
            structuralCleanliness: 0.9,
            titleDetection: title != nil ? 0.9 : 0.3,
            boundaryClarity: 0.95,
            ocrConfidence: 1.0
        )

        let metadata = ImportSourceMetadata(
            fileName: sourceFile,
            pageNumber: pageNumber,
            orderInPage: orderInFile,
            orderInFile: orderInFile,
            boundingBox: nil,
            importTimestamp: importTimestamp
        )

        return ImportedJoke(
            title: title,
            body: jokeText,
            rawSourceText: jokeText,
            tags: tags,
            confidence: importConfidence,
            confidenceFactors: confidenceFactors,
            sourceMetadata: metadata,
            validationResult: .singleJoke,
            extractionMethod: .documentText
        )
    }
}
