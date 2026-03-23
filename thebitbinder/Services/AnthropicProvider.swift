//
//  AnthropicProvider.swift
//  thebitbinder
//
//  Anthropic (Claude) provider — uses the Messages REST API via URLSession.
//  No external SDK required.
//

import Foundation

/// Anthropic provider using the Messages API.
final class AnthropicProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .anthropic

    private let baseURL = "https://api.anthropic.com/v1/messages"

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .anthropic) != nil
    }

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .anthropic) else {
            throw AIProviderError.keyNotConfigured(.anthropic)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": AIProviderType.anthropic.defaultModel,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.anthropic, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.anthropic, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // Parse Anthropic response: { content: [{ type: "text", text: "..." }] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstBlock = contentArray.first,
              let textContent = firstBlock["text"] as? String else {
            throw AIProviderError.apiError(.anthropic, "Unexpected response format")
        }

        return try JokeExtractionPrompt.parseResponse(textContent)
    }
}
