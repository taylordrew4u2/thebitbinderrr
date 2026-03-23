//
//  AIJokeExtractionProvider.swift
//  thebitbinder
//
//  Protocol + concrete providers for multi-provider joke extraction.
//  Supports OpenAI, Arcee, and OpenRouter with automatic fallback.
//

import Foundation
import UIKit

// MARK: - Provider Identity

/// Every extraction provider available for joke extraction.
enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case openAI      = "OpenAI"
    case arceeAI     = "ArceeAI"
    case openRouter  = "OpenRouter"

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .openAI:      return "OpenAI"
        case .arceeAI:     return "Arcee"
        case .openRouter:  return "OpenRouter"
        }
    }

    /// Model used by default for each provider
    var defaultModel: String {
        switch self {
        case .openAI:      return "gpt-4o-mini"
        case .arceeAI:     return "arcee-ai/trinity-large-preview:free"
        case .openRouter:  return "mistralai/mistral-7b-instruct:free"
        }
    }

    /// Where users can get a free API key
    var keySignupURL: URL {
        switch self {
        case .openAI:      return URL(string: "https://platform.openai.com/api-keys")!
        case .arceeAI:     return URL(string: "https://openrouter.ai/keys")!
        case .openRouter:  return URL(string: "https://openrouter.ai/keys")!
        }
    }

    /// SF Symbol for the provider
    var icon: String {
        switch self {
        case .openAI:      return "brain.head.profile"
        case .arceeAI:     return "triangle.fill"
        case .openRouter:  return "arrow.triangle.branch"
        }
    }

    /// The plist key name for this provider's API key
    var plistKey: String {
        switch self {
        case .openAI:      return "OPENAI_API_KEY"
        case .arceeAI:     return "ARCEEAI_API_KEY"
        case .openRouter:  return "OPENROUTER_API_KEY"
        }
    }

    /// The per-provider plist file name (without extension)
    var secretsPlistName: String {
        switch self {
        case .openAI:      return "OpenAI-Secrets"
        case .arceeAI:     return "ArceeAI-Secrets"
        case .openRouter:  return "OpenRouter-Secrets"
        }
    }

    /// UserDefaults key for storing user-entered API keys
    var userDefaultsKey: String {
        switch self {
        case .openAI:      return "ai_key_openai"
        case .arceeAI:     return "ai_key_arceeai"
        case .openRouter:  return "ai_key_openrouter"
        }
    }
}

// MARK: - Provider Errors

enum AIProviderError: LocalizedError {
    case keyNotConfigured(AIProviderType)
    case rateLimited(AIProviderType, retryAfterSeconds: Int?)
    case apiError(AIProviderType, String)
    case noJokesFound(AIProviderType)
    case allProvidersFailed([AIProviderType: Error])

    var errorDescription: String? {
        switch self {
        case .keyNotConfigured(let provider):
            return "\(provider.displayName) is not configured. Add your API key in Settings → API Keys."
        case .rateLimited(let provider, let retry):
            let retryStr = retry.map { " Try again in \($0 / 60) minutes." } ?? ""
            return "\(provider.displayName) rate limit reached.\(retryStr)"
        case .apiError(let provider, let msg):
            return "\(provider.displayName) error: \(msg)"
        case .noJokesFound(let provider):
            return "\(provider.displayName) found no jokes in the provided content."
        case .allProvidersFailed(let errors):
            let names = errors.keys.map(\.displayName).joined(separator: ", ")
            return "All providers failed (\(names)). Falling back to local extraction."
        }
    }
}

// MARK: - Provider Protocol

/// Any AI service that can extract jokes from text.
protocol AIJokeExtractionProvider {
    var providerType: AIProviderType { get }

    /// Check if this provider is configured (has a valid API key).
    func isConfigured() -> Bool

    /// Extract jokes from raw text. Throws `AIProviderError` on failure.
    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke]
}

// MARK: - Shared Prompt

enum JokeExtractionPrompt {
    static func textPrompt(for text: String) -> String {
        let maxChars = 12_000
        let truncated = text.count > maxChars
            ? String(text.prefix(maxChars)) + "\n...[truncated]"
            : text

        return """
        You are a comedy writing assistant. Extract every stand-up joke from the text below.

        CRITICAL: Each joke MUST be a SEPARATE entry. Split on:
        - "NEXT JOKE", "NEW JOKE", "NEW BIT", "---", "***", "===", "//"
        - Numbered items: "1.", "2.", "#1", "Joke 1:"
        - Blank lines, bullet points

        RULES:
        1. When in doubt, SPLIT
        2. One punchline = one entry
        3. Never combine unrelated material

        Return ONLY a valid JSON array (no markdown fences, no extra text):
        [{"jokeText":"<ONE joke>","humorMechanism":"<type or null>","confidence":<0.0-1.0>,"explanation":"<or null>","title":"<or null>","tags":["tag1"]}]

        If no jokes: []

        --- TEXT ---
        \(truncated)
        """
    }

    /// Parse the raw string response into `[GeminiExtractedJoke]`.
    static func parseResponse(_ raw: String) throws -> [GeminiExtractedJoke] {
        var jsonString = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        if jsonString.hasPrefix("```") {
            let lines = jsonString.components(separatedBy: .newlines)
            jsonString = lines.dropFirst().dropLast().joined(separator: "\n")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON array boundaries if there's extra text
        if let start = jsonString.firstIndex(of: "["),
           let end = jsonString.lastIndex(of: "]") {
            jsonString = String(jsonString[start...end])
        }

        guard let data = jsonString.data(using: .utf8) else {
            throw AIProviderError.apiError(.openAI, "Response is not valid UTF-8")
        }

        return try JSONDecoder().decode([GeminiExtractedJoke].self, from: data)
    }
}

// MARK: - API Key Loader (multi-provider)

enum AIKeyLoader {
    /// Loads the API key for a given provider.
    /// Checks: 1) UserDefaults (user-entered), 2) Per-provider plist, 3) Secrets.plist, 4) environment variable.
    static func loadKey(for provider: AIProviderType) -> String? {
        // 1. User-entered key (stored in UserDefaults)
        if let key = UserDefaults.standard.string(forKey: provider.userDefaultsKey),
           !key.isEmpty {
            return key
        }

        // 2. Per-provider plist (e.g., OpenAI-Secrets.plist, ArceeAI-Secrets.plist)
        if let url = Bundle.main.url(forResource: provider.secretsPlistName, withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict[provider.plistKey] as? String,
           !key.isEmpty,
           !key.hasPrefix("YOUR_") {
            return key
        }

        // 3. Main Secrets.plist (fallback for all providers)
        if provider.secretsPlistName != "Secrets",
           let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict[provider.plistKey] as? String,
           !key.isEmpty,
           !key.hasPrefix("YOUR_") {
            return key
        }

        // 4. Environment variable
        if let key = ProcessInfo.processInfo.environment[provider.plistKey],
           !key.isEmpty {
            return key
        }

        return nil
    }

    /// Save a user-entered API key.
    static func saveKey(_ key: String, for provider: AIProviderType) {
        if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.removeObject(forKey: provider.userDefaultsKey)
        } else {
            UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: provider.userDefaultsKey)
        }
    }

    /// Clear the user-entered API key.
    static func clearKey(for provider: AIProviderType) {
        UserDefaults.standard.removeObject(forKey: provider.userDefaultsKey)
    }

    /// Returns all providers that have a configured key.
    static func configuredProviders() -> [AIProviderType] {
        AIProviderType.allCases.filter { loadKey(for: $0) != nil }
    }
}

// MARK: - AI Extracted Joke Model

/// Represents a joke extracted by an AI provider (OpenAI, Arcee, OpenRouter, etc.)
struct GeminiExtractedJoke: Codable, Identifiable, Equatable {
    let id: UUID
    let jokeText: String
    let humorMechanism: String?
    let confidence: Float
    let explanation: String?
    let title: String?
    let tags: [String]
    
    enum CodingKeys: String, CodingKey {
        case jokeText
        case humorMechanism
        case confidence
        case explanation
        case title
        case tags
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.jokeText = try container.decode(String.self, forKey: .jokeText)
        self.humorMechanism = try container.decodeIfPresent(String.self, forKey: .humorMechanism)
        self.confidence = try container.decode(Float.self, forKey: .confidence)
        self.explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jokeText, forKey: .jokeText)
        try container.encodeIfPresent(humorMechanism, forKey: .humorMechanism)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(explanation, forKey: .explanation)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(tags, forKey: .tags)
    }
    
    init(jokeText: String, humorMechanism: String? = nil, confidence: Float = 0.5, explanation: String? = nil, title: String? = nil, tags: [String] = []) {
        self.id = UUID()
        self.jokeText = jokeText
        self.humorMechanism = humorMechanism
        self.confidence = confidence
        self.explanation = explanation
        self.title = title
        self.tags = tags
    }
    
    static func == (lhs: GeminiExtractedJoke, rhs: GeminiExtractedJoke) -> Bool {
        lhs.jokeText == rhs.jokeText &&
        lhs.humorMechanism == rhs.humorMechanism &&
        abs(lhs.confidence - rhs.confidence) < 0.01 &&
        lhs.explanation == rhs.explanation &&
        lhs.title == rhs.title &&
        lhs.tags == rhs.tags
    }
    
    /// Convert this AI-extracted joke to an ImportedJoke for the pipeline
    func toImportedJoke(
        sourceFile: String,
        pageNumber: Int,
        orderInFile: Int,
        importTimestamp: Date
    ) -> ImportedJoke {
        // Map confidence from Float (0.0-1.0) to ImportConfidence
        let importConfidence: ImportConfidence = {
            if confidence >= 0.8 {
                return .high
            } else if confidence >= 0.6 {
                return .medium
            } else {
                return .low
            }
        }()
        
        // Create confidence factors from the joke's confidence
        let factors = ConfidenceFactors(
            extractionQuality: confidence,
            structuralCleanliness: 0.7,
            titleDetection: (title != nil) ? 0.8 : 0.3,
            boundaryClarity: 0.75,
            ocrConfidence: 1.0
        )
        
        // Create metadata
        let metadata = ImportSourceMetadata(
            fileName: sourceFile,
            pageNumber: pageNumber,
            orderInPage: orderInFile,
            orderInFile: orderInFile,
            boundingBox: nil,
            importTimestamp: importTimestamp
        )
        
        // Determine validation result (assume single joke for now)
        let validationResult: ValidationResult = {
            if confidence >= 0.8 {
                return .singleJoke
            } else if confidence >= 0.6 {
                return .singleJoke
            } else {
                return .requiresReview(reasons: ["Low confidence from AI extraction"])
            }
        }()
        
        return ImportedJoke(
            title: title,
            body: jokeText,
            rawSourceText: jokeText,
            tags: tags,
            confidence: importConfidence,
            confidenceFactors: factors,
            sourceMetadata: metadata,
            validationResult: validationResult,
            extractionMethod: .imageOCR
        )
    }
}

// MARK: - Rate Limit Error

struct GeminiRateLimitError: Error {
    let provider: AIProviderType
    let retryAfterSeconds: Int?
    
    var localizedDescription: String {
        let retryStr = retryAfterSeconds.map { " Try again in \($0 / 60) minutes." } ?? ""
        return "\(provider.displayName) rate limit reached.\(retryStr)"
    }
}
