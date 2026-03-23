//
//  GeminiProvider.swift
//  thebitbinder
//
//  Gemini provider — wraps the existing GeminiJokeExtractor for the fallback system.
//

import Foundation
import GoogleGenerativeAI

/// Gemini provider using the Google Generative AI SDK.
final class GeminiProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .gemini

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .gemini) != nil
    }

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .gemini) else {
            throw AIProviderError.keyNotConfigured(.gemini)
        }

        // Check Gemini-specific daily rate limit
        guard DailyRequestTracker.canMakeRequest() else {
            throw AIProviderError.rateLimited(.gemini, retryAfterSeconds: DailyRequestTracker.hoursUntilReset() * 3600)
        }

        let model = GenerativeModel(name: AIProviderType.gemini.defaultModel, apiKey: apiKey)
        let prompt = JokeExtractionPrompt.textPrompt(for: text)
        DailyRequestTracker.increment()

        do {
            let response = try await model.generateContent(prompt)
            guard let raw = response.text else { return [] }
            return try JokeExtractionPrompt.parseResponse(raw)
        } catch let error as AIProviderError {
            throw error
        } catch {
            let desc = error.localizedDescription.lowercased()
            if desc.contains("rate") || desc.contains("quota") || desc.contains("429") {
                throw AIProviderError.rateLimited(.gemini, retryAfterSeconds: nil)
            }
            throw AIProviderError.apiError(.gemini, error.localizedDescription)
        }
    }
}
