import Foundation

/// Apple-native BitBuddy backend.
/// This is structured around an on-device, session-oriented chat model.
/// If the Foundation Models runtime isn't available, callers should use the local fallback backend.
final class FoundationModelsBitBuddyService: BitBuddyBackend {
    static let shared = FoundationModelsBitBuddyService()
    
    private init() {}
    
    var backendName: String { "Foundation Models" }
    var isAvailable: Bool {
        if #available(iOS 18.0, macOS 15.0, *) {
            return false
        }
        return false
    }
    var supportsStreaming: Bool { false }
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        guard isAvailable else {
            throw BitBuddyBackendError.unavailable
        }
        
        // TODO: Wire this to Apple's Foundation Models runtime when that framework is enabled
        // in the target. The service contract is already session-based and local-only.
        // The prompt below documents the intended app-specific behavior.
        let _ = buildPrompt(message: message, session: session, dataContext: dataContext)
        throw BitBuddyBackendError.unavailable
    }
    
    private func buildPrompt(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) -> String {
        let recentTurns = session.turns.suffix(8).map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        let recentJokes = dataContext.recentJokes.prefix(5).map {
            "- \($0.title): \($0.content.prefix(180))"
        }.joined(separator: "\n")
        
        return """
        You are BitBuddy, an on-device comedy writing partner inside BitBinder.
        Be sharp, concise, collaborative, and useful.
        Help with setups, punchlines, tags, rewrites, structure, sequencing, and brainstorming.
        Do not act like a therapist or generic life coach.
        Do not invent facts or pretend to know user material you were not given.
        Prefer concrete rewrites, alternatives, and next-step suggestions.
        If app joke context is available, ground your response in it.
        
        CRITICAL: You MUST ALWAYS respond with valid JSON in this EXACT format and nothing else:
        
        {
          "response": "Your friendly message to the user",
          "action": {
            "type": "add_joke",
            "joke": "full joke text here"
          }
        }
        
        OR for multiple actions:
        
        {
          "response": "Your friendly message to the user", 
          "actions": [
            {
              "type": "add_joke",
              "joke": "first joke text"
            },
            {
              "type": "add_joke", 
              "joke": "second joke text"
            }
          ]
        }
        
        Available action types:
        - "add_joke": Save a joke to the Jokes folder (include "joke" field with full text)
        - More action types coming soon: delete_joke, list_jokes, etc.
        
        If no action is needed, omit the "action"/"actions" field entirely.
        Always return valid JSON only - no extra text before or after.
        
        Examples:
        User: "add a joke: Why did the chicken cross the road? To get to the other side!"
        Response: {"response": "Great classic! I've saved that chicken joke to your collection.", "action": {"type": "add_joke", "joke": "Why did the chicken cross the road? To get to the other side!"}}
        
        User: "help me with timing"
        Response: {"response": "Timing is everything in comedy! Try pausing right before your punchline to build tension. The beat of silence makes the surprise hit harder."}
        
        Conversation so far:
        \(recentTurns)
        
        Recent jokes in the notebook:
        \(recentJokes.isEmpty ? "None provided." : recentJokes)
        
        Latest user message:
        \(message)
        """
    }
}
