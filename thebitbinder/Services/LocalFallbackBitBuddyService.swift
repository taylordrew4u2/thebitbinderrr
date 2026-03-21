import Foundation

/// Fully local fallback for devices where Foundation Models isn't available.
/// Keeps BitBuddy useful without any network calls.
final class LocalFallbackBitBuddyService: BitBuddyBackend {
    static let shared = LocalFallbackBitBuddyService()
    
    private init() {}
    
    var backendName: String { "Local Fallback" }
    var isAvailable: Bool { true }
    var supportsStreaming: Bool { false }
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { 
            return createJSONResponse("Send me a joke, premise, or problem and I'll help punch it up.")
        }
        
        let lower = trimmed.lowercased()
        
        // Check if user wants to add a joke
        if let jokeText = extractJokeFromAddRequest(lower, original: trimmed) {
            return createJSONResponse("Perfect! I've saved that joke to your collection. It's got good energy!", action: ["type": "add_joke", "joke": jokeText])
        }
        
        if lower.contains("tag") || lower.contains("punch up") || lower.contains("punch-up") {
            return createJSONResponse(buildPunchUpResponse(for: trimmed, context: dataContext))
        }
        
        if lower.contains("rewrite") || lower.contains("reword") {
            return createJSONResponse(buildRewriteResponse(for: trimmed, context: dataContext))
        }
        
        if lower.contains("organize") || lower.contains("folder") || lower.contains("categor") {
            return createJSONResponse(buildOrganizationResponse(for: trimmed, context: dataContext))
        }
        
        if lower.contains("set") || lower.contains("order") || lower.contains("sequence") {
            return createJSONResponse(buildSetOrderResponse(context: dataContext))
        }
        
        if lower.contains("title") {
            return createJSONResponse(buildTitleIdeas(for: trimmed))
        }
        
        return createJSONResponse(buildGeneralComedyResponse(for: trimmed, context: dataContext, session: session))
    }
    
    private func buildPunchUpResponse(for message: String, context: BitBuddyDataContext) -> String {
        let anchor = bestAnchor(from: message, context: context)
        return """
        Let’s punch this up around: \(anchor)
        
        Try 3 angles:
        1. Heighten the weirdest detail.
        2. Add a sharper point of view.
        3. End on the most specific image.
        
        Quick tag ideas:
        • What would make this more petty?
        • What’s the dumbest version of this?
        • What’s the most honest thing you’d admit here?
        
        If you want, paste the exact setup and I’ll give you 5 tighter tags.
        """
    }
    
    private func buildRewriteResponse(for message: String, context: BitBuddyDataContext) -> String {
        let anchor = bestAnchor(from: message, context: context)
        return """
        Here’s a cleaner rewrite approach for: \(anchor)
        
        Rewrite passes:
        • Setup: get to the premise faster.
        • Turn: reveal the real opinion sooner.
        • Punch: end on the most surprising specific word.
        
        Template:
        “I thought [normal assumption], but it turns out [sharper truth].”
        
        Send me the current version and I’ll rewrite it short, medium, and aggressive.
        """
    }
    
    private func buildOrganizationResponse(for message: String, context: BitBuddyDataContext) -> String {
        let suggestions = suggestTags(from: message, context: context)
        return """
        Local organization pass:
        
        Good folder/tag directions:
        \(suggestions.map { "• \($0)" }.joined(separator: "\n"))
        
        Rule of thumb:
        • Group by comedic engine first.
        • Split premises that could stand alone.
        • Keep tags with the parent bit unless they clearly became their own joke.
        """
    }
    
    private func buildSetOrderResponse(context: BitBuddyDataContext) -> String {
        let recent = context.recentJokes.prefix(3).map(\.title)
        let examples = recent.isEmpty ? "• Open with a quick hit\n• Put the most personal bit second\n• End with the broadest closer" : recent.enumerated().map { index, title in
            let label = ["Open", "Middle", "Closer"][min(index, 2)]
            return "• \(label): \(title)"
        }.joined(separator: "\n")
        
        return """
        For set order, think in momentum:
        • Start with something clean and easy to trust.
        • Move into the stranger or more specific material after that.
        • Close on the bit with the clearest act-out, escalation, or callback potential.
        
        Draft order:
        \(examples)
        
        If you send 3-5 joke titles, I’ll suggest a tighter sequence.
        """
    }
    
    private func buildTitleIdeas(for message: String) -> String {
        let seed = message.replacingOccurrences(of: "title", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = seed.isEmpty ? "your bit" : seed
        return """
        Working title ideas for \(cleaned):
        • \(titleize(cleaned, fallback: "Specific Weird Detail"))
        • \(titleize(cleaned + " angle", fallback: "Sharper Point Of View"))
        • \(titleize(cleaned + " problem", fallback: "The Real Problem"))
        
        Good titles are short, visual, and specific.
        """
    }
    
    private func buildGeneralComedyResponse(
        for message: String,
        context: BitBuddyDataContext,
        session: BitBuddySessionSnapshot
    ) -> String {
        let anchor = bestAnchor(from: message, context: context)
        let continuity = session.turns.last?.text ?? anchor
        return """
        I’m with you. The strongest handle I see is: \(anchor)
        
        To develop it, pick one lane:
        • make it more specific
        • make the opinion harsher
        • make the image weirder
        • make the logic dumber but committed
        
        Next move:
        Write 2 lines — the clean setup and the meanest or strangest turn.
        
        If you want, I can help you turn “\(continuity.prefix(80))” into:
        1. a tighter one-liner
        2. a story bit
        3. a tag run
        """
    }
    
    private func bestAnchor(from message: String, context: BitBuddyDataContext) -> String {
        if let focused = context.focusedJoke, !focused.title.isEmpty {
            return focused.title
        }
        
        if let recent = context.recentJokes.first(where: { message.localizedCaseInsensitiveContains($0.title) }) {
            return recent.title
        }
        
        let words = message.split(separator: " ").prefix(6).map(String.init).joined(separator: " ")
        return words.isEmpty ? "this bit" : words
    }
    
    private func suggestTags(from message: String, context: BitBuddyDataContext) -> [String] {
        let seedWords = Set(
            message.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 3 }
        )
        
        let existing = context.recentJokes
            .flatMap(\.tags)
            .filter { seedWords.contains($0.lowercased()) }
        
        let defaults = ["Observational", "Relationship", "Work", "Self-Own", "Act-Out", "Callback"]
        return Array((existing + defaults).prefix(5))
    }
    
    private func titleize(_ source: String, fallback: String) -> String {
        let words = source
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(4)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return words.isEmpty ? fallback : words
    }
    
    // MARK: - JSON Response Helpers
    
    /// Creates a JSON response in the required BitBuddy format
    private func createJSONResponse(_ response: String, action: [String: Any]? = nil) -> String {
        var jsonObject: [String: Any] = ["response": response]
        
        if let action = action {
            jsonObject["action"] = action
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            return String(data: jsonData, encoding: .utf8) ?? fallbackResponse(response)
        } catch {
            return fallbackResponse(response)
        }
    }
    
    /// Fallback for when JSON serialization fails - still try to be helpful
    private func fallbackResponse(_ response: String) -> String {
        return "{\"response\": \"\(response.replacingOccurrences(of: "\"", with: "\\\""))\"}"
    }
    
    /// Extracts joke text from "add joke:" type messages
    private func extractJokeFromAddRequest(_ lowerMessage: String, original: String) -> String? {
        let addPatterns = ["add a joke:", "add joke:", "save joke:", "save a joke:", "new joke:"]
        
        for pattern in addPatterns {
            if lowerMessage.contains(pattern) {
                if let range = lowerMessage.range(of: pattern) {
                    let startIndex = original.index(range.upperBound, offsetBy: 0, limitedBy: original.endIndex) ?? original.endIndex
                    let jokeText = String(original[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return jokeText.isEmpty ? nil : jokeText
                }
            }
        }
        
        return nil
    }
}
