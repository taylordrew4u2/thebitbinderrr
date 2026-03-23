//
//  AIJokeExtractionManager.swift
//  thebitbinder
//
//  Manages multiple joke extraction providers with automatic fallback.
//  When one provider fails or hits a rate limit, it tries the next one.
//  Falls back to LocalJokeExtractor as a last resort.
//
//  ⚠️  HARDWIRED RESTRICTION: Extraction is ONLY for file imports.
//  BitBuddy is 100% local/rule-based and must NEVER call extraction providers.
//  All extraction methods require an `AIExtractionToken` that only
//  `ImportPipelineCoordinator` can create.
//

import Foundation
import Network

// MARK: - Caller Restriction Token

/// A zero-cost token that proves the caller is authorised to use extraction.
///
/// **Only `ImportPipelineCoordinator` should create this.**
/// BitBuddy, chat services, and all other subsystems must NEVER
/// instantiate this token. If you find yourself creating one outside
/// of the import pipeline, you are violating the architecture.
struct AIExtractionToken {
    fileprivate(set) var caller: String

    /// Create a token. The `caller` string is recorded for logging/assertions.
    /// This initialiser is intentionally NOT fileprivate so the import pipeline
    /// (in a different file) can create it, but the doc-comment above serves as
    /// the contract. A runtime assertion double-checks at the call-site.
    init(caller: String) {
        self.caller = caller
    }
}

/// Manages extraction providers with automatic fallback for joke extraction.
///
/// ⚠️  Extraction is reserved **exclusively** for the file-import pipeline.
/// BitBuddy is local-only and must never touch these providers.
/// Every public extraction method requires an `AIExtractionToken` that
/// only `ImportPipelineCoordinator` should create.
final class AIJokeExtractionManager {

    static let shared = AIJokeExtractionManager()

    // MARK: - Allowed callers (hardwired)

    /// The ONLY callers permitted to use extraction.
    /// Add an entry here only if a new *import* pathway is created.
    /// BitBuddy, chat, or any interactive feature must NEVER appear here.
    private static let allowedCallers: Set<String> = [
        "ImportPipelineCoordinator"
    ]

    /// Runtime gate — crashes in DEBUG if an unauthorised caller sneaks through.
    private func assertAuthorised(_ token: AIExtractionToken) {
        if !Self.allowedCallers.contains(token.caller) {
            assertionFailure(
                "🚫 [Extraction] BLOCKED: '\(token.caller)' is not allowed to use extraction. "
                + "Extraction is reserved for file imports only. Allowed: \(Self.allowedCallers)"
            )
            print("🚫 [Extraction] BLOCKED: Unauthorised caller '\(token.caller)' — extraction denied.")
        }
    }

    // MARK: - Providers

    private let providers: [AIProviderType: AIJokeExtractionProvider] = [
        .openAI:      OpenAIProvider(),
        .arceeAI:     ArceeAIProvider(),
        .openRouter:  OpenRouterProvider()
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
    /// Defaults to: OpenAI → Arcee → OpenRouter
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

    // MARK: - Extraction with Fallback (import-only)

    /// The main extraction method. Tries each configured provider in order,
    /// falling back on rate limits or errors. Returns the jokes and which provider succeeded.
    ///
    /// ⚠️  Requires an `AIExtractionToken`. Only the file-import pipeline may call this.
    /// BitBuddy and all other features must NEVER call this method.
    func extractJokes(from text: String, token: AIExtractionToken) async -> (jokes: [GeminiExtractedJoke], provider: AIProviderType?, usedLocalFallback: Bool) {
        assertAuthorised(token)

        print("🔍 [Extraction] Starting with \(text.count) chars")
        print("🔍 [Extraction] Providers in use order: \(providerOrder.map(\.displayName).joined(separator: " → "))")

        // Fast network check — if there's no connectivity, skip all providers
        // and go straight to local extraction instead of waiting for timeouts.
        if !Self.hasNetworkConnectivity() {
            print("📡 [Extraction] No network connectivity — using local extraction")
            let localJokes = LocalJokeExtractor.shared.extract(from: text)
            return (localJokes, nil, true)
        }

        var errors: [AIProviderType: Error] = [:]
        var hitNetworkError = false

        for providerType in providerOrder {
            // If a previous provider failed with a network error, don't bother
            // trying the rest — they'll all fail the same way.
            if hitNetworkError {
                print("⏭️ [Extraction] Skipping \(providerType.displayName) (network down)")
                continue
            }

            // Skip disabled providers
            guard !disabledProviders.contains(providerType) else {
                print("⏭️ [Extraction] Skipping \(providerType.displayName) (disabled)")
                continue
            }

            // Skip unconfigured providers
            guard let provider = providers[providerType], provider.isConfigured() else {
                print("⏭️ [Extraction] Skipping \(providerType.displayName) (no API key)")
                continue
            }

            // Skip rate-limited providers
            guard !isRateLimited(providerType) else {
                print("⏭️ [Extraction] Skipping \(providerType.displayName) (rate limited)")
                continue
            }

            // Try this provider
            do {
                print("🔄 [Extraction] Trying \(providerType.displayName)…")
                let jokes = try await provider.extractJokes(from: text)
                print("✅ [Extraction] \(providerType.displayName) returned \(jokes.count) joke(s)")
                return (jokes, providerType, false)
            } catch let error as AIProviderError {
                switch error {
                case .rateLimited(_, let retryAfter):
                    print("⚠️ [Extraction] \(providerType.displayName) rate limited, trying next…")
                    markRateLimited(providerType, forSeconds: retryAfter)
                    errors[providerType] = error
                case .keyNotConfigured:
                    print("⚠️ [Extraction] \(providerType.displayName) key not configured, trying next…")
                    errors[providerType] = error
                default:
                    print("❌ [Extraction] \(providerType.displayName) error: \(error.localizedDescription)")
                    errors[providerType] = error
                }
            } catch {
                print("❌ [Extraction] \(providerType.displayName) unexpected error: \(error.localizedDescription)")

                // Detect network errors — if the network is down, skip remaining providers
                if Self.isNetworkError(error) {
                    print("📡 [Extraction] Network error detected — skipping remaining providers")
                    hitNetworkError = true
                }

                // Check for common rate limit patterns in the error
                let desc = error.localizedDescription.lowercased()
                if desc.contains("rate") || desc.contains("quota") || desc.contains("429") || desc.contains("limit") {
                    markRateLimited(providerType, forSeconds: nil)
                }
                errors[providerType] = error
            }
        }

        // All AI providers failed — fall back to local extraction
        print("🔄 [Extraction] All providers failed, using local rule-based extraction")
        let localJokes = LocalJokeExtractor.shared.extract(from: text)
        return (localJokes, nil, true)
    }

    /// Convenience: extracts jokes for the import pipeline.
    /// When all providers fail, returns local extraction results instead of throwing.
    ///
    /// ⚠️  Requires an `AIExtractionToken`. Only file-import callers may use this.
    func extractJokesForPipeline(from text: String, token: AIExtractionToken) async -> (jokes: [GeminiExtractedJoke], usedLocalFallback: Bool, providerUsed: String) {
        let result = await extractJokes(from: text, token: token)
        let providerName = result.provider?.displayName ?? "Local Extraction"
        return (result.jokes, result.usedLocalFallback, providerName)
    }

    // MARK: - Status Messages

    /// Returns a neutral status message (no provider details exposed).
    var statusMessage: String {
        let available = availableProviders
        if available.isEmpty {
            return "Import tool needs setup. Check Settings for more info."
        } else if available.count == 1 {
            return "Import tool ready! Add more providers for automatic fallback."
        } else {
            return "Import tool ready with \(available.count) providers. If one fails, it'll automatically switch."
        }
    }

    // MARK: - Network Helpers

    /// Quick connectivity check using NWPathMonitor snapshot.
    /// Returns false if the device has no route to the internet.
    private static func hasNetworkConnectivity() -> Bool {
        let monitor = NWPathMonitor()
        let path = monitor.currentPath
        monitor.cancel()
        return path.status == .satisfied
    }

    /// Returns true if the error is a network-level failure
    /// (no route, timeout, DNS, connection refused, etc.).
    static func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // URLSession network errors
        if nsError.domain == NSURLErrorDomain {
            let networkCodes: Set<Int> = [
                NSURLErrorNotConnectedToInternet,   // -1009
                NSURLErrorNetworkConnectionLost,     // -1005
                NSURLErrorCannotFindHost,            // -1003
                NSURLErrorCannotConnectToHost,       // -1004
                NSURLErrorTimedOut,                   // -1001
                NSURLErrorDNSLookupFailed,           // -1006
                NSURLErrorSecureConnectionFailed,    // -1200
                NSURLErrorInternationalRoamingOff,   // -1018
                NSURLErrorDataNotAllowed,            // -1020
            ]
            return networkCodes.contains(nsError.code)
        }

        // POSIX-level errors (from NWConnection / TCP stack)
        if nsError.domain == NSPOSIXErrorDomain {
            // 53 = EHOSTUNREACH (the exact error in the log)
            // 54 = ECONNRESET, 61 = ECONNREFUSED
            return [53, 54, 61].contains(nsError.code)
        }

        // Check underlying error recursively
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNetworkError(underlying)
        }

        // Fallback: check the description for common network keywords
        let desc = error.localizedDescription.lowercased()
        return desc.contains("network") || desc.contains("no route")
            || desc.contains("not connected") || desc.contains("timed out")
            || desc.contains("host") || desc.contains("offline")
    }
}
