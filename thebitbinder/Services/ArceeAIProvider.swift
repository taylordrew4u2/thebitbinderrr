//
//  ArceeAIProvider.swift
//  thebitbinder
//
//  Arcee AI provider — uses Trinity Large Preview (free) via OpenRouter's
//  OpenAI-compatible Chat Completions API.
//  No external SDK required.
//

import Foundation

/// Arcee AI provider using Trinity Large Preview via OpenRouter.
final class ArceeAIProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .arceeAI

    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .arceeAI) != nil
    }

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .arceeAI) else {
            throw AIProviderError.keyNotConfigured(.arceeAI)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": AIProviderType.arceeAI.defaultModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("thebitbinder", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.arceeAI, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.arceeAI, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // OpenRouter uses OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.apiError(.arceeAI, "Unexpected response format")
        }

        return try JokeExtractionPrompt.parseResponse(content)
    }
}
