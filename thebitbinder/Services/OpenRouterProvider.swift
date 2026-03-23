//
//  OpenRouterProvider.swift
//  thebitbinder
//
//  OpenRouter provider — routes to any model available on openrouter.ai
//  using the OpenAI-compatible Chat Completions API.
//  No external SDK required.
//

import Foundation

/// OpenRouter provider — access hundreds of models (including free ones)
/// through a single OpenAI-compatible endpoint.
final class OpenRouterProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .openRouter

    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"

    /// The model to use. Defaults to a free Mistral model; users can change it
    /// by storing a custom model string under the UserDefaults key below.
    private static let modelDefaultsKey = "openrouter_model"
    private var model: String {
        UserDefaults.standard.string(forKey: Self.modelDefaultsKey)
            ?? AIProviderType.openRouter.defaultModel
    }

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .openRouter) != nil
    }

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .openRouter) else {
            throw AIProviderError.keyNotConfigured(.openRouter)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": model,
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
        request.setValue("https://openrouter.ai", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("thebitbinder", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                let retryAfter = (httpResponse.value(forHTTPHeaderField: "retry-after")
                    ?? httpResponse.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.openRouter, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.openRouter, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // OpenRouter uses the OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? "<empty>"
            throw AIProviderError.apiError(.openRouter, "Unexpected response format: \(raw.prefix(200))")
        }

        return try JokeExtractionPrompt.parseResponse(content)
    }
}
