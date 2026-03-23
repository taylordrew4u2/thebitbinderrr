//
//  OpenAIProvider.swift
//  thebitbinder
//
//  OpenAI provider — uses the Chat Completions REST API via URLSession.
//  No external SDK required.
//

import Foundation

/// OpenAI provider using the Chat Completions API.
final class OpenAIProvider: AIJokeExtractionProvider {
    let providerType: AIProviderType = .openAI

    private let baseURL = "https://api.openai.com/v1/chat/completions"

    func isConfigured() -> Bool {
        AIKeyLoader.loadKey(for: .openAI) != nil
    }

    func extractJokes(from text: String) async throws -> [GeminiExtractedJoke] {
        guard let apiKey = AIKeyLoader.loadKey(for: .openAI) else {
            throw AIProviderError.keyNotConfigured(.openAI)
        }

        let prompt = JokeExtractionPrompt.textPrompt(for: text)

        let requestBody: [String: Any] = [
            "model": AIProviderType.openAI.defaultModel,
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
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Int.init)
                throw AIProviderError.rateLimited(.openAI, retryAfterSeconds: retryAfter)
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIProviderError.apiError(.openAI, "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        // Parse OpenAI response: { choices: [{ message: { content: "..." } }] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.apiError(.openAI, "Unexpected response format")
        }

        return try JokeExtractionPrompt.parseResponse(content)
    }
}
