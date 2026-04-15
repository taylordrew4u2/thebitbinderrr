//
//  BitBuddyService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/18/26.
//

import Foundation
import AVFoundation

/// BitBuddy — Your on-device comedy writing assistant.
/// 100% local and rule-based. NEVER uses AI providers.
/// Extraction providers (OpenAI, Arcee, OpenRouter) are reserved exclusively for file-import
/// joke extraction and are token-gated via `AIExtractionToken`.
/// Powered by a 93-intent router that covers all 11 app sections.
@MainActor
final class BitBuddyService: NSObject, ObservableObject {
    static let shared = BitBuddyService()
    
    // MARK: - Dependencies
    private let authService = AuthService.shared
    private let backend: BitBuddyBackend
    private let intentRouter = BitBuddyIntentRouter.shared
    
    // MARK: - State
    @Published var isLoading = false
    /// Human-readable status message shown in the chat while BitBuddy is working.
    /// Updated at each processing stage so the user knows the app hasn't frozen.
    @Published var statusMessage: String = ""
    /// Whether the backend is reachable. Always `true` for the local engine.
    @Published var isConnected: Bool
    @Published private(set) var backendName: String
    /// Published so the UI can navigate to the section an intent targets.
    @Published var pendingNavigation: BitBuddySection? = nil
    /// Last structured response for action dispatch.
    @Published private(set) var lastActions: [BitBuddyAction] = []
    
    private let maxConversationTurns = 16
    /// Maximum number of old conversations to retain in memory
    private let maxRetainedConversations = 3
    private var conversationId: String?
    private var turnsByConversation: [String: [BitBuddyTurn]] = [:]
    private var recentJokeProvider: (() -> [BitBuddyJokeSummary])?
    
    /// Actions that modify user data and must NOT be dispatched from a route-only
    /// match (i.e. when the backend response is conversational text, not a structured
    /// JSON payload with validated fields).
    private static let dataMutatingActions: Set<String> = [
        "add_joke", "save_joke", "save_joke_in_folder",
        "edit_joke", "rename_joke", "delete_joke", "restore_deleted_joke",
        "delete_brainstorm_note", "delete_set_list", "delete_recording",
        "delete_folder", "remove_joke_from_set", "reject_imported_joke",
        "add_brainstorm_note", "add_roast_joke", "create_roast_target",
        "save_notebook_text", "approve_imported_joke",
    ]
    
    private override init() {
        let selectedBackend = BitBuddyBackendFactory.makeBackend()
        self.backend = selectedBackend
        self.backendName = selectedBackend.backendName
        self.isConnected = selectedBackend.isAvailable
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
        statusMessage = "Thinking…"
        defer {
            isLoading = false
            statusMessage = ""
        }
        
        lastActions = []
        pendingNavigation = nil
        
        let activeConversationId = conversationId ?? UUID().uuidString
        conversationId = activeConversationId
        appendTurn(.init(role: .user, text: message), conversationId: activeConversationId)
        
        let session = BitBuddySessionSnapshot(
            conversationId: activeConversationId,
            turns: turnsByConversation[activeConversationId] ?? []
        )
        
        // Route the intent
        let routeResult = intentRouter.route(message)
        
        // Update status based on what we're about to do
        if let route = routeResult {
            statusMessage = statusHint(for: route.intent.id)
        }
        
        var dataContext = BitBuddyDataContext()
        dataContext.userName = UserDefaults.standard.string(forKey: "userName") ?? "Comedian"
        dataContext.recentJokes = recentJokeProvider?() ?? []
        dataContext.routedIntent = routeResult
        dataContext.activeSection = routeResult?.section
        dataContext.isRoastMode = UserDefaults.standard.bool(forKey: "roastModeEnabled")
        
        do {
            let rawResponse: String
            statusMessage = statusMessage.isEmpty ? "Thinking…" : statusMessage
            do {
                rawResponse = try await backend.send(message: message, session: session, dataContext: dataContext)
            } catch {
                // Primary backend failed (e.g. MLX model not downloaded).
                // Fall through to the always-available local engine so the
                // user never sees a blank error in chat.
                if backend is LocalFallbackBitBuddyService {
                    throw error   // already the fallback — nothing left to try
                }
                print(" [BitBuddy] Primary backend (\(backend.backendName)) failed: \(error.localizedDescription). Falling back to local engine.")
                rawResponse = try await LocalFallbackBitBuddyService.shared.send(
                    message: message, session: session, dataContext: dataContext
                )
            }
            
            // Process the response through our JSON handler (handles
            // any future structured-JSON backends). For the local
            // rule-based backend this is a no-op pass-through.
            let displayText = handleBitBuddyResponse(rawResponse)
            
            // Dispatch the structured action from the routed intent.
            // The local backend returns plain text (never JSON), so
            // handleBitBuddyResponse's JSON path never fires. We
            // dispatch directly from the route result instead.
            //
            // IMPORTANT: Only dispatch non-mutating actions from the route
            // result alone. Data-mutating actions (save_joke, delete_joke, etc.)
            // require a validated structured payload — executing them from a
            // conversational response with no payload causes empty saves,
            // "missing joke text" errors, and bad UI loops.
            if let route = routeResult {
                if !Self.dataMutatingActions.contains(route.intent.id) {
                    let intentAction: [String: Any] = [
                        "type": route.intent.id
                    ]
                    executeBitBuddyAction(intentAction)
                }
                
                // Publish navigation target for the UI — only for explicit
                // navigation intents. All other intents return a text response
                // that the user should be able to read inside the chat.
                if route.category == .navigation && route.section != .bitbuddy {
                    pendingNavigation = route.section
                }
            }
            
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
        // Remove the old conversation's turns to free memory
        if let oldId = conversationId {
            turnsByConversation.removeValue(forKey: oldId)
        }
        conversationId = nil
        // isConnected stays true — the local backend is always available.
        pendingNavigation = nil
        lastActions = []
        
        // Evict oldest conversations if we're retaining too many
        while turnsByConversation.count > maxRetainedConversations {
            // Remove the conversation with the fewest turns (likely the oldest/least active)
            if let leastActiveKey = turnsByConversation.min(by: { $0.value.count < $1.value.count })?.key {
                turnsByConversation.removeValue(forKey: leastActiveKey)
            } else {
                break
            }
        }
    }
    
    /// Clear the pending navigation (call after the UI has acted on it).
    func clearPendingNavigation() {
        pendingNavigation = nil
    }
    
    /// Expose the intent router for UI components that want to show suggestions.
    var router: BitBuddyIntentRouter { intentRouter }
    
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
    /// Updates the original `Joke` objects in-place so changes are visible
    /// to SwiftData without creating detached copies.
    func analyzeMultipleJokes(_ jokes: [Joke]) async throws -> [String: [Joke]] {
        var categorized: [String: [Joke]] = [:]
        
        for joke in jokes {
            let analysis = try await analyzeJoke(joke.content)
            
            // Update the original in-place — no detached copies
            joke.category = analysis.category
            joke.tags = analysis.tags
            joke.difficulty = analysis.difficulty
            joke.humorRating = analysis.humorRating
            
            categorized[analysis.category, default: []].append(joke)
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
        // NOTE: recordedAudioURL is NOT deleted here.
        // stopRecording() returns the URL and clears the reference.
        // Callers are responsible for the file after stopRecording().
        // Deleting it here would silently lose unprocessed recordings.
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
        statusMessage = "Processing audio…"
        defer {
            isLoading = false
            statusMessage = ""
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw BitBuddyError.invalidResponse
        }
        
        // Transcribe the audio using on-device speech recognition
        statusMessage = "Transcribing your recording…"
        let transcriptionService = AudioTranscriptionService.shared
        do {
            let result = try await transcriptionService.transcribe(audioURL: audioURL)
            let transcript = result.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                return try await sendMessage("I recorded something but couldn't make out any words. Could you help me brainstorm instead?")
            }
            // Send the actual transcribed text for analysis
            statusMessage = "Analyzing your idea…"
            return try await sendMessage("Analyze this idea I just recorded: \(transcript)")
        } catch {
            print(" [BitBuddy] Transcription failed: \(error.localizedDescription)")
            // Fall back gracefully — the user still gets a response
            return try await sendMessage("I recorded an audio note but transcription wasn't available. Can you help me brainstorm some ideas?")
        }
    }
    
    // MARK: - JSON Response Handling
    
    /// Handles structured JSON responses from BitBuddy and executes any actions
    /// - Parameter rawResponse: The raw response string from the LLM
    /// - Returns: The cleaned response text to display in the chat UI
    func handleBitBuddyResponse(_ rawResponse: String) -> String {
        print(" [BitBuddy] Raw response: \(rawResponse.prefix(120))")
        
        // Try to parse as JSON — only structured JSON responses can trigger actions.
        // Plain-text conversational responses are returned as-is with NO action dispatch.
        guard let jsonData = rawResponse.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Not JSON — this is a normal conversational response. Do NOT try to
            // execute any action path. This prevents treating "Sure, Taylor! What's
            // the next joke?" as a save_joke payload.
            return rawResponse
        }
        
        // Extract the response text
        let responseText = jsonObject["response"] as? String ?? rawResponse
        
        // Handle single action — requires valid JSON with explicit action payload
        if let actionDict = jsonObject["action"] as? [String: Any] {
            // Validate that data-mutating actions have required fields before dispatch
            if validateActionPayload(actionDict) {
                executeBitBuddyAction(actionDict)
            } else {
                print(" [BitBuddy] Skipping action dispatch — payload validation failed")
            }
        }
        
        // Handle multiple actions
        if let actionsArray = jsonObject["actions"] as? [[String: Any]] {
            for actionDict in actionsArray {
                if validateActionPayload(actionDict) {
                    executeBitBuddyAction(actionDict)
                } else {
                    print(" [BitBuddy] Skipping action in array — payload validation failed")
                }
            }
        }
        
        return responseText
    }
    
    /// Validates that a data-mutating action payload contains the required fields.
    /// Non-mutating actions (navigation, status checks) pass through without validation.
    private func validateActionPayload(_ action: [String: Any]) -> Bool {
        guard let actionType = action["type"] as? String else { return false }
        
        // Non-mutating actions don't need payload validation
        guard Self.dataMutatingActions.contains(actionType) else { return true }
        
        // Specific field requirements for data-mutating actions
        switch actionType {
        case "add_joke", "save_joke", "save_joke_in_folder":
            guard let joke = action["joke"] as? String, !joke.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print(" [BitBuddy] Blocked \(actionType): missing or empty 'joke' field")
                return false
            }
        case "add_brainstorm_note", "save_notebook_text":
            guard let text = action["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print(" [BitBuddy] Blocked \(actionType): missing or empty 'text' field")
                return false
            }
        case "add_roast_joke":
            guard let joke = action["joke"] as? String, !joke.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print(" [BitBuddy] Blocked \(actionType): missing or empty 'joke' field")
                return false
            }
        default:
            // Other mutating actions pass if they have any non-type key
            break
        }
        return true
    }
    
    /// Executes a single BitBuddy action
    /// - Parameter action: Dictionary containing action type and parameters
    private func executeBitBuddyAction(_ action: [String: Any]) {
        guard let actionType = action["type"] as? String else {
            print(" [BitBuddy] Invalid action - missing type")
            return
        }
        
        print(" [BitBuddy] Executing action: \(actionType)")
        
        // Build a structured action for downstream consumers
        var params: [String: String] = [:]
        for (key, value) in action where key != "type" {
            if let str = value as? String { params[key] = str }
        }
        let structuredAction = BitBuddyAction(type: actionType, parameters: params)
        lastActions.append(structuredAction)
        
        // Dispatch by intent category
        switch actionType {

        //  Jokes 
        case "add_joke", "save_joke":
            handleAddJokeAction(action)
        case "save_joke_in_folder":
            handleAddJokeAction(action) // folder param handled inside
        case "edit_joke":
            print(" [BitBuddy] edit_joke routed — UI will present editor")
        case "rename_joke":
            print(" [BitBuddy] rename_joke routed")
        case "delete_joke":
            print(" [BitBuddy] delete_joke routed")
        case "restore_deleted_joke":
            print(" [BitBuddy] restore_deleted_joke routed")
        case "mark_hit":
            print(" [BitBuddy] mark_hit routed")
        case "unmark_hit":
            print(" [BitBuddy] unmark_hit routed")
        case "add_tags":
            print(" [BitBuddy] add_tags routed")
        case "remove_tags":
            print(" [BitBuddy] remove_tags routed")
        case "move_joke_folder":
            print(" [BitBuddy] move_joke_folder routed")
        case "create_folder":
            print(" [BitBuddy] create_folder routed")
        case "rename_folder":
            print(" [BitBuddy] rename_folder routed")
        case "delete_folder":
            print(" [BitBuddy] delete_folder routed")
        case "search_jokes":
            print(" [BitBuddy] search_jokes routed")
        case "filter_jokes_recent", "filter_jokes_by_folder", "filter_jokes_by_tag":
            print(" [BitBuddy] filter routed: \(actionType)")
        case "list_hits":
            print(" [BitBuddy] list_hits routed")
        case "share_joke":
            print(" [BitBuddy] share_joke routed")
        case "duplicate_joke":
            print(" [BitBuddy] duplicate_joke routed")
        case "merge_jokes":
            print(" [BitBuddy] merge_jokes routed")

        //  Brainstorm 
        case "add_brainstorm_note":
            print(" [BitBuddy] add_brainstorm_note routed")
        case "voice_capture_idea":
            print(" [BitBuddy] voice_capture_idea routed")
        case "edit_brainstorm_note":
            print(" [BitBuddy] edit_brainstorm_note routed")
        case "delete_brainstorm_note":
            print(" [BitBuddy] delete_brainstorm_note routed")
        case "promote_idea_to_joke":
            print(" [BitBuddy] promote_idea_to_joke routed")
        case "search_brainstorm":
            print(" [BitBuddy] search_brainstorm routed")
        case "group_brainstorm_topics":
            print(" [BitBuddy] group_brainstorm_topics routed")

        //  Set Lists 
        case "create_set_list":
            print(" [BitBuddy] create_set_list routed")
        case "rename_set_list":
            print(" [BitBuddy] rename_set_list routed")
        case "delete_set_list":
            print(" [BitBuddy] delete_set_list routed")
        case "add_joke_to_set":
            print(" [BitBuddy] add_joke_to_set routed")
        case "remove_joke_from_set":
            print(" [BitBuddy] remove_joke_from_set routed")
        case "reorder_set":
            print(" [BitBuddy] reorder_set routed")
        case "estimate_set_time":
            print(" [BitBuddy] estimate_set_time routed")
        case "shuffle_set":
            print(" [BitBuddy] shuffle_set routed")
        case "suggest_set_opener":
            print(" [BitBuddy] suggest_set_opener routed")
        case "suggest_set_closer":
            print(" [BitBuddy] suggest_set_closer routed")
        case "present_set":
            print(" [BitBuddy] present_set routed")
        case "find_set_list":
            print(" [BitBuddy] find_set_list routed")

        //  Recordings 
        case "start_recording":
            print(" [BitBuddy] start_recording routed")
        case "stop_recording":
            print(" [BitBuddy] stop_recording routed")
        case "rename_recording":
            print(" [BitBuddy] rename_recording routed")
        case "delete_recording":
            print(" [BitBuddy] delete_recording routed")
        case "play_recording":
            print(" [BitBuddy] play_recording routed")
        case "transcribe_recording":
            print(" [BitBuddy] transcribe_recording routed")
        case "search_transcripts":
            print(" [BitBuddy] search_transcripts routed")
        case "clip_recording":
            print(" [BitBuddy] clip_recording routed")
        case "attach_recording_to_set":
            print(" [BitBuddy] attach_recording_to_set routed")
        case "review_set_from_recording":
            print(" [BitBuddy] review_set_from_recording routed")

        //  BitBuddy Writing 
        case "analyze_joke":
            print(" [BitBuddy] analyze_joke — handled by backend")
        case "improve_joke":
            print(" [BitBuddy] improve_joke — handled by backend")
        case "generate_premise":
            print(" [BitBuddy] generate_premise — handled by backend")
        case "generate_joke":
            print(" [BitBuddy] generate_joke — handled by backend")
        case "summarize_style":
            print(" [BitBuddy] summarize_style — handled by backend")
        case "suggest_unexplored_topics":
            print(" [BitBuddy] suggest_unexplored_topics — handled by backend")
        case "find_similar_jokes":
            print(" [BitBuddy] find_similar_jokes — handled by backend")
        case "shorten_joke":
            print(" [BitBuddy] shorten_joke — handled by backend")
        case "expand_joke":
            print(" [BitBuddy] expand_joke — handled by backend")
        case "generate_tags_for_joke":
            print(" [BitBuddy] generate_tags_for_joke — handled by backend")
        case "rewrite_in_my_style":
            print(" [BitBuddy] rewrite_in_my_style — handled by backend")
        case "crowdwork_help":
            print(" [BitBuddy] crowdwork_help — handled by backend")
        case "roast_line_generation":
            print(" [BitBuddy] roast_line_generation — handled by backend")
        case "compare_versions":
            print(" [BitBuddy] compare_versions — handled by backend")
        case "extract_premises_from_notes":
            print(" [BitBuddy] extract_premises_from_notes — handled by backend")
        case "explain_comedy_theory":
            print(" [BitBuddy] explain_comedy_theory — handled by backend")

        //  Notebook 
        case "open_notebook":
            print(" [BitBuddy] open_notebook routed")
            // Navigation handled centrally in sendMessage via routeResult
        case "save_notebook_text":
            print(" [BitBuddy] save_notebook_text routed")
        case "attach_photo_to_notebook":
            print(" [BitBuddy] attach_photo_to_notebook routed")
        case "search_notebook":
            print(" [BitBuddy] search_notebook routed")

        //  Roast Mode 
        case "toggle_roast_mode":
            let current = UserDefaults.standard.bool(forKey: "roastModeEnabled")
            UserDefaults.standard.set(!current, forKey: "roastModeEnabled")
            print(" [BitBuddy] toggle_roast_mode  \(!current)")
        case "create_roast_target":
            print(" [BitBuddy] create_roast_target routed")
        case "add_roast_joke":
            print(" [BitBuddy] add_roast_joke routed")
        case "search_roasts":
            print(" [BitBuddy] search_roasts routed")
        case "create_roast_set":
            print(" [BitBuddy] create_roast_set routed")
        case "present_roast_set":
            print(" [BitBuddy] present_roast_set routed")
        case "attach_photo_to_target":
            print(" [BitBuddy] attach_photo_to_target routed")

        //  Import 
        case "import_file":
            print(" [BitBuddy] import_file routed — triggering file picker in chat")
            NotificationCenter.default.post(name: .bitBuddyTriggerFileImport, object: nil)
        case "import_image":
            print(" [BitBuddy] import_image routed")
        case "review_import_queue":
            print(" [BitBuddy] review_import_queue routed")
        case "approve_imported_joke":
            print(" [BitBuddy] approve_imported_joke routed")
        case "reject_imported_joke":
            print(" [BitBuddy] reject_imported_joke routed")
        case "edit_imported_joke":
            print(" [BitBuddy] edit_imported_joke routed")
        case "check_import_limit":
            print(" [BitBuddy] check_import_limit routed")
        case "show_import_history":
            print(" [BitBuddy] show_import_history routed")

        //  Sync 
        case "check_sync_status":
            print(" [BitBuddy] check_sync_status routed")
        case "sync_now":
            print(" [BitBuddy] sync_now — triggering manual sync")
            Task { @MainActor in await iCloudSyncService.shared.syncNow() }
        case "toggle_icloud_sync":
            print(" [BitBuddy] toggle_icloud_sync routed")

        //  Settings 
        case "export_all_jokes":
            print(" [BitBuddy] export_all_jokes routed")
        case "export_recordings":
            print(" [BitBuddy] export_recordings routed")
        case "clear_cache":
            print(" [BitBuddy] clear_cache — clearing temp files")
            clearTempFiles()

        //  Help 
        case "open_help_faq":
            print(" [BitBuddy] open_help_faq routed")
            // Navigation handled centrally in sendMessage via routeResult
        case "explain_feature":
            print(" [BitBuddy] explain_feature — handled by backend")

        default:
            print(" [BitBuddy] Unknown action type: \(actionType)")
        }
    }
    
    /// Handles the add_joke action — publishes the joke text so the UI layer
    /// can create a proper SwiftData `Joke` with the active `ModelContext`.
    ///
    ///   This used to write a `.txt` file to Documents/Jokes, which was
    /// invisible to the SwiftData-backed UI. Fixed to publish via
    /// `NotificationCenter` so any listening view can persist it correctly.
    private func handleAddJokeAction(_ action: [String: Any]) {
        guard let jokeText = action["joke"] as? String, !jokeText.isEmpty else {
            print(" [BitBuddy] add_joke action missing joke text")
            return
        }

        let folder = action["folder"] as? String
        print(" [BitBuddy] Publishing add_joke for UI persistence")
        print(" [BitBuddy] Joke content: \(jokeText.prefix(50))...")

        NotificationCenter.default.post(
            name: .bitBuddyAddJoke,
            object: nil,
            userInfo: [
                "jokeText": jokeText,
                "folder": folder as Any
            ]
        )
    }
    
    // MARK: - Private helpers
    
    /// Returns a user-facing status hint for the given intent so the chat
    /// shows what BitBuddy is working on instead of a generic spinner.
    private func statusHint(for intentId: String) -> String {
        switch intentId {
        // Joke writing / analysis
        case "analyze_joke":                     return "Analyzing your joke…"
        case "improve_joke":                     return "Crafting improvements…"
        case "generate_premise":                 return "Brainstorming premises…"
        case "generate_joke":                    return "Writing jokes…"
        case "shorten_joke":                     return "Tightening the punchline…"
        case "expand_joke":                      return "Expanding the bit…"
        case "rewrite_in_my_style":              return "Studying your style…"
        case "find_similar_jokes":               return "Searching your library…"
        case "generate_tags_for_joke":           return "Generating tags…"
        case "compare_versions":                 return "Comparing versions…"
        case "extract_premises_from_notes":      return "Extracting premises…"
        case "explain_comedy_theory":            return "Looking that up…"
        case "summarize_style":                  return "Analyzing your style…"
        case "suggest_unexplored_topics":        return "Scanning for fresh topics…"
        // Roast
        case "roast_line_generation":            return "Loading the burns…"
        case "crowdwork_help":                   return "Prepping crowd work…"
        // Set lists
        case "create_set_list":                  return "Building your set list…"
        case "estimate_set_time":                return "Calculating set time…"
        case "suggest_set_opener", "suggest_set_closer": return "Picking the perfect bit…"
        case "reorder_set":                      return "Reordering your set…"
        // Recordings
        case "transcribe_recording":             return "Transcribing audio…"
        // Import
        case "import_file":                      return "Preparing file import…"
        // Sync
        case "sync_now":                         return "Syncing…"
        case "check_sync_status":                return "Checking sync status…"
        // Search
        case _ where intentId.hasPrefix("search"), _ where intentId.hasPrefix("filter"), _ where intentId.hasPrefix("find"):
            return "Searching…"
        default:
            return "Thinking…"
        }
    }
    
    /// Removes all files from the app's temporary directory.
    /// Safe to call at any time — only affects throwaway caches/scratch files.
    private func clearTempFiles() {
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) else { return }
        var removed = 0
        for file in files {
            do {
                try FileManager.default.removeItem(at: file)
                removed += 1
            } catch {
                // Temp files in use — skip silently
            }
        }
        print(" [BitBuddy] Cleared \(removed) temp file(s)")
    }
    
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
