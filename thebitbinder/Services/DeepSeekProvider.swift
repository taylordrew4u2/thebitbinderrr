//
//  DeepSeekProvider.swift
//  thebitbinder
//
//  DeepSeek provider — uses the OpenAI-compatible Chat Completions API.
//  No external SDK required.
//

import Foundation

/// DeepSeek provider using the OpenAI-compatible Chat Completions API.
final class DeepSeekProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .deepSeek

    private let baseURL = "https://api.deepseek.com/chat/completions"

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .deepSeek) != nil
    }

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .deepSeek) else {
            throw AIProviderError.keyNotConfigured(.deepSeek)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": AIProviderType.deepSeek.defaultModel,
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
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.deepSeek, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.deepSeek, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // DeepSeek uses OpenAI-compatible response format
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.apiError(.deepSeek, "Unexpected response format")
        }

        return try JokeExtractionPrompt.parseResponse(content)
    }
}
