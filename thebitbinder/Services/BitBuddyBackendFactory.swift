import Foundation

/// BitBuddy backend factory.
///
/// BitBuddy is 100% local and rule-based. It does NOT use any AI service.
/// Extraction providers (OpenAI, Arcee, OpenRouter) are reserved exclusively for
/// the GagGrabber file-import joke-extraction pipeline.
/// All AI extraction requires an `AIExtractionToken` — see AIJokeExtractionManager.
enum BitBuddyBackendFactory {
    static func makeBackend() -> BitBuddyBackend {
        // Always return the local fallback — BitBuddy never calls AI.
        return LocalFallbackBitBuddyService.shared
    }
}
