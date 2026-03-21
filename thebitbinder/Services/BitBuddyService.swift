//
//  BitBuddyService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/18/26.
//

import Foundation
import AVFoundation

/// BitBuddy — Your comedy writing assistant.
/// Uses on-device backends only: Foundation Models when available,
/// otherwise a local rule-based fallback that keeps chat functional offline.
@MainActor
final class BitBuddyService: NSObject, ObservableObject {
    static let shared = BitBuddyService()
    
    // MARK: - Dependencies
    private let authService = AuthService.shared
    private let backend: BitBuddyBackend
    
    // MARK: - State
    @Published var isLoading = false
    @Published var isConnected = false
    @Published private(set) var backendName: String
    
    private let maxConversationTurns = 16
    private var conversationId: String?
    private var turnsByConversation: [String: [BitBuddyTurn]] = [:]
    private var recentJokeProvider: (() -> [BitBuddyJokeSummary])?
    
    private override init() {
        let selectedBackend = BitBuddyBackendFactory.makeBackend()
        self.backend = selectedBackend
        self.backendName = selectedBackend.backendName
        super.init()
    }
    
    // MARK: - Public API
    
    /// Optional hook so BitBuddy can ground responses in current app joke data.
    func registerJokeDataProvider(_ provider: @escaping () -> [BitBuddyJokeSummary]) {
        recentJokeProvider = provider
    }
    
    /// Send a text message and get a response from the local BitBuddy backend.
    func sendMessage(_ message: String) async throws -> String {
        try await authService.ensureAuthenticated()
        
        isLoading = true
        defer { isLoading = false }
        
        let activeConversationId = conversationId ?? UUID().uuidString
        conversationId = activeConversationId
        appendTurn(.init(role: .user, text: message), conversationId: activeConversationId)
        
        let session = BitBuddySessionSnapshot(
            conversationId: activeConversationId,
            turns: turnsByConversation[activeConversationId] ?? []
        )
        let dataContext = BitBuddyDataContext(recentJokes: recentJokeProvider?() ?? [])
        
        do {
            let rawResponse = try await backend.send(message: message, session: session, dataContext: dataContext)
            
            // Process the response through our new JSON handler
            let displayText = handleBitBuddyResponse(rawResponse)
            
            appendTurn(.init(role: .assistant, text: displayText), conversationId: activeConversationId)
            isConnected = true
            return displayText
        } catch {
            isConnected = false
            throw error
        }
    }
    
    /// Start a new conversation.
    func startNewConversation() {
        if let conversationId {
            turnsByConversation[conversationId] = []
        }
        conversationId = nil
        isConnected = false
    }
    
    /// Analyze a single joke and return category, tags, difficulty, and humor rating.
    /// Local-only heuristic fallback keeps this feature working without external APIs.
    func analyzeJoke(_ jokeText: String) async throws -> JokeAnalysis {
        try await authService.ensureAuthenticated()
        
        let lower = jokeText.lowercased()
        let category = inferCategory(from: lower)
        let tags = inferTags(from: lower)
        let difficulty = inferDifficulty(from: jokeText)
        let humorRating = inferHumorRating(from: jokeText)
        
        return JokeAnalysis(
            category: category,
            tags: tags,
            difficulty: difficulty,
            humorRating: humorRating
        )
    }
    
    /// Extract jokes from raw text using local structural heuristics.
    func extractJokes(from text: String) async throws -> [String] {
        try await authService.ensureAuthenticated()
        
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let rawParts = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        var jokes: [String] = []
        var currentBlock: [String] = []
        
        for line in rawParts {
            if line.isEmpty {
                if !currentBlock.isEmpty {
                    jokes.append(currentBlock.joined(separator: "\n"))
                    currentBlock.removeAll()
                }
                continue
            }
            
            let isBullet = line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*")
            let isNumbered = line.range(of: #"^\d+[\.)]\s"#, options: .regularExpression) != nil
            
            if (isBullet || isNumbered), !currentBlock.isEmpty {
                jokes.append(currentBlock.joined(separator: "\n"))
                currentBlock = [stripListMarker(from: line)]
            } else {
                currentBlock.append(isBullet || isNumbered ? stripListMarker(from: line) : line)
            }
        }
        
        if !currentBlock.isEmpty {
            jokes.append(currentBlock.joined(separator: "\n"))
        }
        
        let filtered = jokes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if filtered.isEmpty, !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [normalized.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        
        return filtered
    }
    
    /// Analyze multiple jokes and group them by category.
    func analyzeMultipleJokes(_ jokes: [Joke]) async throws -> [String: [Joke]] {
        var categorized: [String: [Joke]] = [:]
        
        for joke in jokes {
            let analysis = try await analyzeJoke(joke.content)
            if categorized[analysis.category] == nil {
                categorized[analysis.category] = []
            }
            
            let updatedJoke = Joke(content: joke.content, title: joke.title, folder: joke.folder)
            updatedJoke.category = analysis.category
            updatedJoke.tags = analysis.tags
            updatedJoke.difficulty = analysis.difficulty
            updatedJoke.humorRating = analysis.humorRating
            categorized[analysis.category]?.append(updatedJoke)
        }
        
        return categorized
    }
    
    /// Get organization suggestions for a set of jokes using local reasoning.
    func getOrganizationSuggestions(for jokes: [Joke]) async throws -> String {
        try await authService.ensureAuthenticated()
        
        let grouped = Dictionary(grouping: jokes) { inferCategory(from: $0.content.lowercased()) }
        let lines = grouped.keys.sorted().map { category in
            let count = grouped[category]?.count ?? 0
            return "• \(category): \(count) joke\(count == 1 ? "" : "s")"
        }
        
        return """
        Here’s a local organization pass:
        \(lines.joined(separator: "\n"))
        
        Suggested order:
        1. Start with the most accessible observational material.
        2. Group darker or weirder bits once trust is built.
        3. Save act-out or callback-heavy material for later in the set.
        """
    }
    
    // MARK: - Audio Recording/Playback
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordedAudioURL: URL? = nil
    
    func cleanupAudioResources() {
        audioRecorder?.stop()
        audioRecorder = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if let url = recordedAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedAudioURL = nil
    }
    
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("bitbuddy_recording.m4a")
        recordedAudioURL = fileURL
        
        audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.record()
    }
    
    func stopRecording() -> URL? {
        audioRecorder?.stop()
        let url = recordedAudioURL
        recordedAudioURL = nil
        return url
    }
    
    func playAudio(from url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
    
    func playAudio(data: Data) throws {
        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }
    
    func sendAudio(_ audioURL: URL) async throws -> String {
        try await authService.ensureAuthenticated()
        
        isLoading = true
        defer { isLoading = false }
        
        guard (try? Data(contentsOf: audioURL)) != nil else {
            throw BitBuddyError.invalidResponse
        }
        
        return try await sendMessage("User sent an audio message and wants feedback on the recorded idea.")
    }
    
    // MARK: - JSON Response Handling
    
    /// Handles structured JSON responses from BitBuddy and executes any actions
    /// - Parameter rawResponse: The raw response string from the LLM
    /// - Returns: The cleaned response text to display in the chat UI
    func handleBitBuddyResponse(_ rawResponse: String) -> String {
        print("🤖 [BitBuddy] Raw response: \(rawResponse)")
        
        // Try to parse as JSON
        guard let jsonData = rawResponse.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("⚠️ [BitBuddy] Failed to parse JSON, returning raw response")
            return rawResponse
        }
        
        // Extract the response text
        let responseText = jsonObject["response"] as? String ?? rawResponse
        
        // Handle single action
        if let actionDict = jsonObject["action"] as? [String: Any] {
            executeBitBuddyAction(actionDict)
        }
        
        // Handle multiple actions
        if let actionsArray = jsonObject["actions"] as? [[String: Any]] {
            for actionDict in actionsArray {
                executeBitBuddyAction(actionDict)
            }
        }
        
        return responseText
    }
    
    /// Executes a single BitBuddy action
    /// - Parameter action: Dictionary containing action type and parameters
    private func executeBitBuddyAction(_ action: [String: Any]) {
        guard let actionType = action["type"] as? String else {
            print("❌ [BitBuddy] Invalid action - missing type")
            return
        }
        
        print("🎬 [BitBuddy] Executing action: \(actionType)")
        
        switch actionType {
        case "add_joke":
            handleAddJokeAction(action)
        default:
            print("⚠️ [BitBuddy] Unknown action type: \(actionType)")
        }
    }
    
    /// Handles the add_joke action - saves a joke to the Jokes folder
    /// - Parameter action: Action dictionary containing the joke text
    private func handleAddJokeAction(_ action: [String: Any]) {
        guard let jokeText = action["joke"] as? String, !jokeText.isEmpty else {
            print("❌ [BitBuddy] add_joke action missing joke text")
            return
        }
        
        do {
            // Get Documents directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let jokesFolder = documentsURL.appendingPathComponent("Jokes")
            
            // Create Jokes folder if it doesn't exist
            if !FileManager.default.fileExists(atPath: jokesFolder.path) {
                try FileManager.default.createDirectory(at: jokesFolder, withIntermediateDirectories: true)
                print("📁 [BitBuddy] Created Jokes folder")
            }
            
            // Create filename with timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "joke_\(timestamp).txt"
            let fileURL = jokesFolder.appendingPathComponent(filename)
            
            // Save the joke to file
            try jokeText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ [BitBuddy] Saved joke to: \(filename)")
            print("💾 [BitBuddy] Joke content: \(jokeText.prefix(50))...")
            
        } catch {
            print("❌ [BitBuddy] Failed to save joke: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private helpers
    
    private func appendTurn(_ turn: BitBuddyTurn, conversationId: String) {
        var turns = turnsByConversation[conversationId] ?? []
        turns.append(turn)
        if turns.count > maxConversationTurns {
            turns = Array(turns.suffix(maxConversationTurns))
        }
        turnsByConversation[conversationId] = turns
    }
    
    private func stripListMarker(from line: String) -> String {
        line
            .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+[\.)]\s*"#, with: "", options: .regularExpression)
    }
    
    private func inferCategory(from lower: String) -> String {
        if lower.contains("dating") || lower.contains("girlfriend") || lower.contains("boyfriend") || lower.contains("wife") || lower.contains("husband") {
            return "Relationships"
        }
        if lower.contains("work") || lower.contains("office") || lower.contains("boss") || lower.contains("coworker") || lower.contains("job") {
            return "Work"
        }
        if lower.contains("family") || lower.contains("mom") || lower.contains("dad") || lower.contains("parent") || lower.contains("child") {
            return "Family"
        }
        if lower.contains("airplane") || lower.contains("airport") || lower.contains("uber") || lower.contains("driving") || lower.contains("travel") {
            return "Travel"
        }
        if lower.contains("phone") || lower.contains("app") || lower.contains("internet") || lower.contains("ai") || lower.contains("tech") {
            return "Technology"
        }
        if lower.contains("body") || lower.contains("doctor") || lower.contains("therapy") || lower.contains("anxiety") || lower.contains("gym") {
            return "Personal"
        }
        return "Observational"
    }
    
    private func inferTags(from lower: String) -> [String] {
        let candidatePairs: [(String, String)] = [
            ("dating", "dating"), ("relationship", "relationship"), ("work", "work"),
            ("family", "family"), ("travel", "travel"), ("airport", "airport"),
            ("tech", "tech"), ("phone", "phone"), ("gym", "gym"),
            ("therapy", "therapy"), ("money", "money"), ("food", "food")
        ]
        let tags = candidatePairs.compactMap { lower.contains($0.0) ? $0.1.capitalized : nil }
        return Array(tags.prefix(3))
    }
    
    private func inferDifficulty(from text: String) -> String {
        if text.count < 60 { return "Easy" }
        if text.count < 180 { return "Medium" }
        return "Hard"
    }
    
    private func inferHumorRating(from text: String) -> Int {
        let lengthBonus = min(text.count / 40, 3)
        let punctuationBonus = text.contains("?") || text.contains("!") ? 1 : 0
        return min(5 + lengthBonus + punctuationBonus, 9)
    }
}

// MARK: - Models

struct JokeAnalysis {
    let category: String
    let tags: [String]
    let difficulty: String
    let humorRating: Int
}

// MARK: - Errors

enum BitBuddyError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError
    case notConnected
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from BitBuddy"
        case .apiError(_, let message):
            return message
        case .parseError:
            return "BitBuddy couldn't understand that request"
        case .notConnected:
            return "BitBuddy isn't available right now"
        }
    }
}

extension BitBuddyService: AVAudioRecorderDelegate {}
extension BitBuddyService: AVAudioPlayerDelegate {}
