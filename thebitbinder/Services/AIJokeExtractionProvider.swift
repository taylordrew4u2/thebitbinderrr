//
//  AIJokeExtractionProvider.swift
//  thebitbinder
//
//  Protocol + concrete providers for multi-API joke extraction.
//  Supports Gemini, OpenAI, Anthropic, and Groq with automatic fallback.
//

import Foundation
import UIKit

// MARK: - Provider Identity

/// Every AI provider that GagGrabber can use for joke extraction.
enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case gemini    = "Gemini"
    case openAI    = "OpenAI"
    case deepSeek  = "DeepSeek"
    case anthropic = "Anthropic"
    case groq      = "Groq"

    var id: String { rawValue }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .gemini:   return "Google Gemini"
        case .openAI:   return "OpenAI (GPT)"
        case .deepSeek: return "DeepSeek"
        case .anthropic: return "Anthropic (Claude)"
        case .groq:     return "Groq"
        }
    }

    /// Model used by default for each provider
    var defaultModel: String {
        switch self {
        case .gemini:   return "gemini-2.0-flash"
        case .openAI:   return "gpt-4o-mini"
        case .deepSeek: return "deepseek-chat"
        case .anthropic: return "claude-3-5-haiku-20241022"
        case .groq:     return "llama-3.1-70b-versatile"
        }
    }

    /// Where users can get a free API key
    var keySignupURL: URL {
        switch self {
        case .gemini:   return URL(string: "https://aistudio.google.com/app/apikey")!
        case .openAI:   return URL(string: "https://platform.openai.com/api-keys")!
        case .deepSeek: return URL(string: "https://platform.deepseek.com/api_keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .groq:     return URL(string: "https://console.groq.com/keys")!
        }
    }

    /// SF Symbol for the provider
    var icon: String {
        switch self {
        case .gemini:   return "sparkle"
        case .openAI:   return "brain.head.profile"
        case .deepSeek: return "magnifyingglass.circle.fill"
        case .anthropic: return "bubble.left.and.text.bubble.right"
        case .groq:     return "bolt.fill"
        }
    }

    /// The plist key name for this provider's API key
    var plistKey: String {
        switch self {
        case .gemini:   return "GEMINI_API_KEY"
        case .openAI:   return "OPENAI_API_KEY"
        case .deepSeek: return "DEEPSEEK_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .groq:     return "GROQ_API_KEY"
        }
    }

    /// The per-provider plist file name (without extension)
    var secretsPlistName: String {
        switch self {
        case .gemini:   return "Secrets"          // legacy — stays in Secrets.plist
        case .openAI:   return "OpenAI-Secrets"
        case .deepSeek: return "DeepSeek-Secrets"
        case .anthropic: return "Anthropic-Secrets"
        case .groq:     return "Groq-Secrets"
        }
    }
    
    /// UserDefaults key for storing user-entered API keys
    var userDefaultsKey: String {
        switch self {
        case .gemini:   return "ai_key_gemini"
        case .openAI:   return "ai_key_openai"
        case .deepSeek: return "ai_key_deepseek"
        case .anthropic: return "ai_key_anthropic"
        case .groq:     return "ai_key_groq"
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
            return "All AI providers failed (\(names)). Falling back to local extraction."
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
            throw AIProviderError.apiError(.gemini, "Response is not valid UTF-8")
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

        // 2. Per-provider plist (e.g., OpenAI-Secrets.plist, DeepSeek-Secrets.plist)
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
