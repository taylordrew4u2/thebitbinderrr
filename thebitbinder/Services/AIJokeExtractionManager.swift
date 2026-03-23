//
//  AIJokeExtractionManager.swift
//  thebitbinder
//
//  Manages multiple AI providers with automatic fallback.
//  When one provider hits a rate limit or fails, it tries the next one.
//  Falls back to LocalJokeExtractor as a last resort.
//

import Foundation

/// Manages AI providers with automatic fallback for joke extraction.
/// Tries providers in the user's preferred order, skipping ones without keys,
/// and falling through on rate limits or errors.
final class AIJokeExtractionManager {

    static let shared = AIJokeExtractionManager()

    // MARK: - Providers

    private let providers: [AIProviderType: AIJokeExtractionProvider] = [
        .gemini:   GeminiProvider(),
        .openAI:   OpenAIProvider(),
        .deepSeek: DeepSeekProvider(),
        .anthropic: AnthropicProvider(),
        .groq:     GroqProvider()
    ]

    /// UserDefaults key for the user's preferred provider order.
    private let orderKey = "ai_provider_order"

    /// UserDefaults key for disabled providers.
    private let disabledKey = "ai_disabled_providers"

    /// Tracks which providers are temporarily rate-limited so we skip them.
    private var rateLimitedUntil: [AIProviderType: Date] = [:]

    private init() {}

    // MARK: - Provider Order

    /// Returns the user's preferred provider order.
    /// Defaults to: Gemini → OpenAI → Anthropic → Groq
    var providerOrder: [AIProviderType] {
        get {
            if let data = UserDefaults.standard.data(forKey: orderKey),
               let decoded = try? JSONDecoder().decode([AIProviderType].self, from: data) {
                // Make sure any new providers that were added are included
                let missing = AIProviderType.allCases.filter { !decoded.contains($0) }
                return decoded + missing
            }
            return AIProviderType.allCases
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: orderKey)
            }
        }
    }

    /// Set of providers the user has manually disabled.
    var disabledProviders: Set<AIProviderType> {
        get {
            if let data = UserDefaults.standard.data(forKey: disabledKey),
               let decoded = try? JSONDecoder().decode(Set<AIProviderType>.self, from: data) {
                return decoded
            }
            return []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: disabledKey)
            }
        }
    }

    /// Toggle a provider enabled/disabled.
    func setProvider(_ provider: AIProviderType, enabled: Bool) {
        var disabled = disabledProviders
        if enabled {
            disabled.remove(provider)
        } else {
            disabled.insert(provider)
        }
        disabledProviders = disabled
    }

    /// Move a provider to a new position in the order.
    func moveProvider(_ provider: AIProviderType, to index: Int) {
        var order = providerOrder
        order.removeAll { $0 == provider }
        let clampedIndex = min(index, order.count)
        order.insert(provider, at: clampedIndex)
        providerOrder = order
    }

    // MARK: - Status

    /// Returns providers that are configured (have keys) and enabled.
    var availableProviders: [AIProviderType] {
        providerOrder.filter { provider in
            !disabledProviders.contains(provider) &&
            (providers[provider]?.isConfigured() ?? false)
        }
    }

    /// Returns all providers with their current status.
    func providerStatuses() -> [(type: AIProviderType, configured: Bool, enabled: Bool, rateLimited: Bool)] {
        providerOrder.map { type in
            let configured = providers[type]?.isConfigured() ?? false
            let enabled = !disabledProviders.contains(type)
            let limited = isRateLimited(type)
            return (type: type, configured: configured, enabled: enabled, rateLimited: limited)
        }
    }

    /// Check if a provider is currently rate-limited.
    private func isRateLimited(_ provider: AIProviderType) -> Bool {
        guard let until = rateLimitedUntil[provider] else { return false }
        if Date() > until {
            rateLimitedUntil[provider] = nil
            return false
        }
        return true
    }

    /// Mark a provider as rate-limited for a duration.
    private func markRateLimited(_ provider: AIProviderType, forSeconds seconds: Int?) {
        let duration = TimeInterval(seconds ?? 3600) // Default: 1 hour
        rateLimitedUntil[provider] = Date().addingTimeInterval(duration)
    }

    // MARK: - Extraction with Fallback

    /// The main extraction method. Tries each configured provider in order,
    /// falling back on rate limits or errors. Returns the jokes and which provider succeeded.
    func extractJokes(from text: String) async -> (jokes: [GeminiExtractedJoke], provider: AIProviderType?, usedLocalFallback: Bool) {
        var errors: [AIProviderType: Error] = [:]

        for providerType in providerOrder {
            // Skip disabled providers
            guard !disabledProviders.contains(providerType) else {
                print("⏭️ [AIManager] Skipping \(providerType.displayName) (disabled)")
                continue
            }

            // Skip unconfigured providers
            guard let provider = providers[providerType], provider.isConfigured() else {
                print("⏭️ [AIManager] Skipping \(providerType.displayName) (no API key)")
                continue
            }

            // Skip rate-limited providers
            guard !isRateLimited(providerType) else {
                print("⏭️ [AIManager] Skipping \(providerType.displayName) (rate limited)")
                continue
            }

            // Try this provider
            do {
                print("🤖 [AIManager] Trying \(providerType.displayName)…")
                let jokes = try await provider.extractJokes(from: text)
                print("✅ [AIManager] \(providerType.displayName) returned \(jokes.count) joke(s)")
                return (jokes, providerType, false)
            } catch let error as AIProviderError {
                switch error {
                case .rateLimited(_, let retryAfter):
                    print("⚠️ [AIManager] \(providerType.displayName) rate limited, trying next…")
                    markRateLimited(providerType, forSeconds: retryAfter)
                    errors[providerType] = error
                case .keyNotConfigured:
                    print("⚠️ [AIManager] \(providerType.displayName) key not configured, trying next…")
                    errors[providerType] = error
                default:
                    print("❌ [AIManager] \(providerType.displayName) error: \(error.localizedDescription)")
                    errors[providerType] = error
                }
            } catch {
                print("❌ [AIManager] \(providerType.displayName) unexpected error: \(error.localizedDescription)")
                // Check for common rate limit patterns in the error
                let desc = error.localizedDescription.lowercased()
                if desc.contains("rate") || desc.contains("quota") || desc.contains("429") || desc.contains("limit") {
                    markRateLimited(providerType, forSeconds: nil)
                }
                errors[providerType] = error
            }
        }

        // All AI providers failed — fall back to local extraction
        print("🔄 [AIManager] All AI providers failed, using local rule-based extraction")
        let localJokes = LocalJokeExtractor.shared.extract(from: text)
        return (localJokes, nil, true)
    }

    /// Convenience: extracts jokes and throws if needed (for pipeline compatibility).
    /// When all providers fail, returns local extraction results instead of throwing.
    func extractJokesForPipeline(from text: String) async -> (jokes: [GeminiExtractedJoke], usedLocalFallback: Bool, providerUsed: String) {
        let result = await extractJokes(from: text)
        let providerName = result.provider?.displayName ?? "Local Extraction"
        return (result.jokes, result.usedLocalFallback, providerName)
    }

    // MARK: - Silly Status Messages

    /// Returns a fun GagGrabber-style status message about the current AI provider state.
    var statusMessage: String {
        let available = availableProviders
        if available.isEmpty {
            return "🤖 GagGrabber has no AI engines configured! Add an API key in Settings to unlock smart joke extraction."
        } else if available.count == 1 {
            return "🤖 GagGrabber is running on \(available[0].displayName). Add more API keys for backup!"
        } else {
            let names = available.map(\.displayName).joined(separator: " → ")
            return "🤖 GagGrabber has \(available.count) AI engines ready: \(names). Rate limit? No problem!"
        }
    }
}
