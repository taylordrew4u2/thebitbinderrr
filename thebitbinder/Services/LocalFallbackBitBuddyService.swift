import Foundation

/// BitBuddy's local rule-based engine — the ONLY backend for chat.
/// AI services are reserved exclusively for the GagGrabber joke-extraction pipeline.
/// Powered by the 93-intent router for structured command handling across 11 app sections.
final class LocalFallbackBitBuddyService: BitBuddyBackend {
    static let shared = LocalFallbackBitBuddyService()
    
    private init() {}
    
    var backendName: String { "Local Fallback" }
    var isAvailable: Bool { true }
    var supportsStreaming: Bool { false }
    
    // MARK: - Mutable State (accessed only on main actor via singleton pattern)
    // SAFETY: userProfile is mutated only from send() which is called exclusively
    // by BitBuddyService (a @MainActor singleton). BitBuddyService serializes
    // access via its isLoading guard. Do NOT call send() from a non-main-actor context.
    nonisolated(unsafe) private var userProfile: UserStyleProfile = .empty()
    private let intentRouter = BitBuddyIntentRouter.shared
    
    func send(
        message: String,
        session: BitBuddySessionSnapshot,
        dataContext: BitBuddyDataContext
    ) async throws -> String {
        // Simulate typing delay for UX
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        // Refresh profile on every request since it's local and fast
        updateProfile(from: dataContext.recentJokes)
        
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use the intent router first
        if let route = dataContext.routedIntent ?? intentRouter.route(trimmed) {
            return handleRoutedIntent(route, message: trimmed, dataContext: dataContext)
        }
        
        // Legacy prefix matching for backwards compat
        let lower = trimmed.lowercased()
        
        if lower.starts(with: "analyze") {
            let content = extractContent(from: trimmed, prefix: "analyze")
            return analyze(content)
        }
        if lower.starts(with: "improve") {
            let content = extractContent(from: trimmed, prefix: "improve")
            return improve(content)
        }
        if lower.starts(with: "premise") {
            let content = extractContent(from: trimmed, prefix: "premise")
            return premise(content)
        }
        if lower.starts(with: "generate") {
            let content = extractContent(from: trimmed, prefix: "generate")
            return generate(content)
        }
        if lower.starts(with: "style") {
            return style()
        }
        if lower.starts(with: "suggest_topic") || lower.contains("suggest topic") {
            return suggestTopic()
        }
        
        // Friendly fallback with section-aware help
        return buildHelpResponse(for: dataContext)
    }
    
    // MARK: - Intent-Routed Dispatch
    
    private func handleRoutedIntent(_ route: BitBuddyRouteResult, message: String, dataContext: BitBuddyDataContext) -> String {
        let intent = route.intent
        let entities = route.extractedEntities
        let userName = dataContext.userName
        
        switch intent.id {
            
        // ═══════════════════════════════════════════
        // JOKES
        // ═══════════════════════════════════════════
        case "save_joke":
            return "✅ Got it, \(userName)! I'll save that joke to your collection. Head to Jokes to see it."
        case "save_joke_in_folder":
            let folder = entities["folder"] ?? "your folder"
            return "📂 Saved! I've filed this joke under \(folder). You can find it in the Jokes section."
        case "edit_joke":
            return "📝 Opening the joke editor — make your changes and I'll keep the original safe in case you want to revert."
        case "rename_joke":
            let title = entities["title"] ?? entities["quoted_value"] ?? "the new title"
            return "📝 Renamed! This joke is now called \"\(title)\". You can find it under the new name in Jokes."
        case "delete_joke":
            return "🗑️ Joke moved to trash. You can restore it anytime from the Trash section if you change your mind."
        case "restore_deleted_joke":
            return "♻️ Restored! That joke is back in your collection right where it belongs."
        case "mark_hit":
            return "⭐ Marked as a Hit! This joke is now in your proven material. You've earned that star."
        case "unmark_hit":
            return "Removed from The Hits. The joke is still saved — it just lost its star status."
        case "add_tags":
            let tags = entities["value"] ?? entities["quoted_value"] ?? "tags"
            return "🏷️ Tags added! Labeled with \(tags). Use tags to filter your jokes later."
        case "remove_tags":
            return "🏷️ Tags removed. This joke is now untagged — a blank canvas."
        case "move_joke_folder":
            let folder = entities["folder"] ?? "the new folder"
            return "📂 Moved! This joke is now filed under \(folder)."
        case "create_folder":
            let folder = entities["value"] ?? entities["quoted_value"] ?? "New Folder"
            return "📁 Folder \"\(folder)\" created! Start adding jokes to it."
        case "rename_folder":
            return "📁 Folder renamed! The new name is live across all your jokes."
        case "delete_folder":
            return "📁 Folder deleted. Any jokes inside have been moved to unfiled."
        case "search_jokes":
            let query = entities["value"] ?? "your search"
            return "🔍 Searching your jokes for \"\(query)\"... Head to the Jokes tab to see results."
        case "filter_jokes_recent":
            return "📅 Here's what you've been working on recently. Check the Jokes tab for your latest material."
        case "filter_jokes_by_folder":
            let folder = entities["folder"] ?? "that folder"
            return "📂 Filtering by \(folder). Switch to the Jokes tab to see everything in that folder."
        case "filter_jokes_by_tag":
            return "🏷️ Filtering by tag. Open Jokes to see the matching material."
        case "list_hits":
            return "⭐ Opening The Hits — your proven material that lands every time. Head to Jokes and filter by Hits to see them."
        case "share_joke":
            return "📤 Joke ready to share! I'll open the share sheet so you can send it however you like."
        case "duplicate_joke":
            return "📋 Duplicated! You now have a fresh copy to experiment with without risking the original."
        case "merge_jokes":
            return "🔀 I'll pull these versions together. Check the merged result in Jokes and see if the combined version hits harder."
            
        // ═══════════════════════════════════════════
        // BRAINSTORM
        // ═══════════════════════════════════════════
        case "add_brainstorm_note":
            return "💡 Idea captured! It's pinned to your Brainstorm board as a sticky note. Come back to it whenever inspiration strikes."
        case "voice_capture_idea":
            return "🎙️ Voice capture ready! Tap the mic button on the Brainstorm page to start speaking your idea."
        case "edit_brainstorm_note":
            return "📝 Opening that brainstorm note for editing. Polish it up!"
        case "delete_brainstorm_note":
            return "🗑️ Brainstorm note deleted. Sometimes clearing the board makes room for the next big idea."
        case "promote_idea_to_joke":
            return "🎭 Promoted! That brainstorm idea is now a full joke in your collection. Time to start writing the setup and punchline."
        case "search_brainstorm":
            let query = entities["value"] ?? "that topic"
            return "🔍 Searching your brainstorm notes for \"\(query)\"... Head to the Brainstorm tab."
        case "group_brainstorm_topics":
            return "📊 Grouping your brainstorm notes by topic... Head to Brainstorm to see which ideas cluster together. You might find a whole chunk hiding in there."
            
        // ═══════════════════════════════════════════
        // SET LISTS
        // ═══════════════════════════════════════════
        case "create_set_list":
            let name = entities["set_name"] ?? entities["quoted_value"] ?? "New Set"
            return "📋 Set list \"\(name)\" created! Start adding jokes to build your lineup."
        case "rename_set_list":
            return "📝 Set list renamed! The new title is live."
        case "delete_set_list":
            return "🗑️ Set list deleted. Those jokes are still saved individually — just the list is gone."
        case "add_joke_to_set":
            return "➕ Joke added to the set list! Drag to reorder if you want it in a different slot."
        case "remove_joke_from_set":
            return "➖ Removed from the set list. The joke is still in your collection."
        case "reorder_set":
            return "↕️ Set reordered! Your lineup is updated. Remember: strong opener, build in the middle, killer closer."
        case "estimate_set_time":
            return "⏱️ Rule of thumb: most comics average about 1–2 minutes per joke on stage. A tight 5-minute set is usually 3–5 jokes, a 10-minute set is 5–8. Open your set list to see the exact joke count and do the math!"
        case "shuffle_set":
            return "🔀 Set shuffled! Sometimes a random order reveals pairings you'd never have thought of. Try reading it through."
        case "suggest_set_opener":
            return "🎤 For an opener, pick something accessible — a relatable observation or a quick-hit joke that doesn't need context. Your most crowd-friendly material goes first."
        case "suggest_set_closer":
            return "🎤 Close with your strongest material — the joke with the biggest reaction. Callbacks work great as closers too. Leave them wanting more."
        case "present_set":
            return "📺 Entering performance mode! Your set list is ready to go — swipe through joke by joke on stage."
        case "find_set_list":
            return "🔍 Searching your set lists... Head to the Set Lists tab to see the match."
            
        // ═══════════════════════════════════════════
        // RECORDINGS
        // ═══════════════════════════════════════════
        case "start_recording":
            return "🔴 Recording started! I'll capture everything. Tap stop when you're done."
        case "stop_recording":
            return "⏹️ Recording saved! You can play it back, transcribe it, or attach it to a set list."
        case "rename_recording":
            return "📝 Recording renamed! Give it a title that'll jog your memory about the set."
        case "delete_recording":
            return "🗑️ Recording deleted. Audio files take up space, so good call if it wasn't a keeper."
        case "play_recording":
            return "▶️ Playing back your recording. Listen for the laughs — and the silences."
        case "transcribe_recording":
            return "📝 Transcription started! This will convert your set audio into searchable text. Check back in Recordings when it's done."
        case "search_transcripts":
            let query = entities["value"] ?? "that word"
            return "🔍 Searching transcripts for \"\(query)\"... I'll pull up every set where you mentioned it."
        case "clip_recording":
            return "✂️ Clip tool ready! Select the start and end points in the Recordings tab to extract just the good part."
        case "attach_recording_to_set":
            return "🔗 Recording attached to the set list! Now you can compare what you wrote to what you actually said on stage."
        case "review_set_from_recording":
            return "📊 Reviewing your set recording... I'll look for strong moments, improv additions, and spots where the energy dipped."
            
        // ═══════════════════════════════════════════
        // BITBUDDY
        // ═══════════════════════════════════════════
        case "analyze_joke":
            let content = extractContent(from: message, prefix: "analyze")
            return analyze(content.isEmpty ? message : content)
        case "improve_joke":
            let content = extractContent(from: message, prefix: "improve")
            return improve(content.isEmpty ? message : content)
        case "generate_premise":
            let content = extractContent(from: message, prefix: "premise")
            return premise(content)
        case "generate_joke":
            let content = extractContent(from: message, prefix: "generate")
            return generate(content)
        case "summarize_style":
            return style()
        case "suggest_unexplored_topics":
            return suggestTopic()
        case "find_similar_jokes":
            return "🔗 Scanning your joke book for similar material... Check Jokes for any overlap or repeated angles."
        case "shorten_joke":
            return """
            ✂️ To tighten this joke:
            • Cut the setup to the absolute minimum context needed.
            • Remove filler words (just, really, basically, kind of).
            • End on the funniest word — don't explain after the punchline.
            • If the audience can infer it, don't say it.
            """
        case "expand_joke":
            return """
            📐 To expand this into a full bit:
            • Add a second beat — what happens next?
            • Tag it: find 2–3 additional angles on the same premise.
            • Build a callback you can use later in the set.
            • Add an act-out or voice to make it physical.
            """
        case "generate_tags_for_joke":
            let content = message
            let tags = inferTagsFromContent(content)
            return "🏷️ Suggested tags: \(tags.isEmpty ? "observational, personal" : tags.joined(separator: ", ")). These help you filter and find similar material later."
        case "rewrite_in_my_style":
            let profileInfo = userProfile.summary.isEmpty ? "I don't have enough of your jokes yet to match your style" : "Based on your style (\(userProfile.summary))"
            return "🎭 \(profileInfo) — try rewriting with your most-used structure and keep the word count around \(Int(userProfile.avgWordCount)) words."
        case "crowdwork_help":
            return """
            👥 Crowdwork starters:
            • "Where are you guys from?" → Riff on the city/neighborhood.
            • "What do you do for work?" → Find the absurd angle.
            • "How long have you two been together?" → The answer is always comedy gold.
            • "Who dragged who here tonight?" → Sets up a power dynamic to play with.
            Keep it light and curious — never punching down at someone who didn't sign up for it.
            """
        case "roast_line_generation":
            return """
            🔥 Roast formula:
            • Observation + Exaggeration: "You look like [person] if they [absurd condition]."
            • Comparison: "[Target] is so [trait] that [consequence]."
            • Callback: Reference something they said/did earlier and twist it.
            Write 5 lines, keep 2. The best roast jokes feel specific and earned.
            """
        case "compare_versions":
            return """
            ⚖️ To compare joke versions:
            • Read both out loud — which one flows better?
            • Check: Which setup is shorter? Shorter usually wins.
            • Which punchline has a harder consonant at the end? (K, T, P sounds hit harder.)
            • Which version could stand alone without context?
            """
        case "extract_premises_from_notes":
            return "📝 Mining your notes for premises... Look for any sentence that starts with an observation or frustration — those are your premises. The formula: [Thing] + [What's weird about it] = premise."
            
        // ═══════════════════════════════════════════
        // NOTEBOOK
        // ═══════════════════════════════════════════
        case "open_notebook":
            return "📓 Opening Notebook! This is your scratch pad — anything goes."
        case "save_notebook_text":
            return "📓 Saved to your Notebook! Quick notes add up — review them weekly for hidden gems."
        case "attach_photo_to_notebook":
            return "📸 Photo attached to your Notebook! Great for saving set lists from the stage, whiteboard ideas, or inspiration."
        case "search_notebook":
            let query = entities["value"] ?? "your search"
            return "🔍 Searching Notebook for \"\(query)\"... Head to the Notebook tab to see matches."
            
        // ═══════════════════════════════════════════
        // ROAST MODE
        // ═══════════════════════════════════════════
        case "toggle_roast_mode":
            let isCurrentlyRoast = dataContext.isRoastMode
            return isCurrentlyRoast
                ? "Roast Mode OFF. Back to your regularly scheduled comedy. 🎭"
                : "🔥 ROAST MODE ACTIVATED. Everything's darker from here. Let's write some burns."
        case "create_roast_target":
            let target = entities["target"] ?? entities["quoted_value"] ?? "your target"
            return "🎯 Roast target \"\(target)\" created! Start adding burns and roast material under their profile."
        case "add_roast_joke":
            let target = entities["target"] ?? "the target"
            return "🔥 Burn filed under \(target)! The roast arsenal grows."
        case "search_roasts":
            return "🔍 Searching your roast material... Head to Roast Mode to see the results."
        case "create_roast_set":
            return "📋 Roast set created! Add your sharpest burns and order them for maximum damage."
        case "present_roast_set":
            return "📺 Roast presentation mode ready! Swipe through your burns on stage. Destroy with precision."
        case "attach_photo_to_target":
            return "📸 Photo attached to the roast target! Now you'll never forget that face."
            
        // ═══════════════════════════════════════════
        // IMPORT
        // ═══════════════════════════════════════════
        case "import_file":
            return """
            📥 **GagGrabber — File Import**
            
            Here's how to import jokes from a file:
            1. Go to **Jokes** tab → tap the **+** button (top right)
            2. Choose **"Import Files"** from the menu
            3. Select your file — GagGrabber supports:
               • **PDF** (text or scanned) — best results
               • **Text files** (.txt, .md)
               • **Documents** (.doc, .docx, .rtf)
            4. GagGrabber will extract individual jokes automatically
            5. Review each one — accept, edit, or skip
            
            💡 **Tips for best results:**
            • One joke per paragraph works best
            • Clear line breaks between jokes help accuracy
            • Typed text extracts better than handwritten
            """
        case "import_image":
            return """
            📸 **GagGrabber — Image Import**
            
            Two ways to import from images:
            
            **Option A — Camera Scan:**
            1. Jokes tab → **+** → **"Scan from Camera"**
            2. Point your camera at your notes
            3. It auto-detects the page edges
            4. Tap the shutter, then "Save"
            
            **Option B — Photo Library:**
            1. Jokes tab → **+** → **"Import Photos"**
            2. Select one or more photos
            
            GagGrabber uses OCR to read the text, then extracts individual jokes.
            
            💡 **Tips for best results:**
            • Good lighting, minimal shadows
            • Keep the page flat and square to the camera
            • Typed/printed text works best; neat handwriting works too
            • High-contrast (dark ink on white paper) gives the best OCR
            """
        case "review_import_queue":
            return """
            📋 **Import Review Queue**
            
            After GagGrabber extracts jokes, you'll see a card-by-card review:
            • **Swipe right** or tap ✅ to accept a joke
            • **Swipe left** or tap ❌ to skip it
            • Tap ✏️ **Edit** to fix the text before saving
            • Tap 💡 **Idea** to send it to Brainstorm instead
            
            High-confidence jokes are auto-accepted (you'll see a green banner).
            You can still review those by scrolling back through the dots.
            
            When you're done, tap **"Save & Finish"** to add everything to your collection.
            """
        case "approve_imported_joke":
            return "✅ Approved! This joke will be saved to your collection when you tap \"Save & Finish\" at the end of the review."
        case "reject_imported_joke":
            return "❌ Skipped. This extracted joke won't be saved. You can go back to it using the dots at the top if you change your mind."
        case "edit_imported_joke":
            return """
            📝 **Editing an Imported Joke**
            
            Tap the ✏️ **Edit** button on the review card to:
            • Fix the title (or add one if GagGrabber didn't detect it)
            • Clean up the joke text — merge broken lines, fix OCR errors
            • The original source text is shown below for reference
            
            When you're happy with it, tap **Done**, then accept the card.
            """
        case "check_import_limit":
            return "📊 GagGrabber extractions are currently **unlimited**! Import as many files as you want. You can check your import history from the Jokes tab → ⋯ menu → **Import History**."
        case "show_import_history":
            return "📜 To see your import history: Jokes tab → tap the **⋯** menu (top left) → **Import History**. You'll see every file you've imported, how many jokes were extracted, and any unresolved fragments."
            
        // ═══════════════════════════════════════════
        // SYNC
        // ═══════════════════════════════════════════
        case "check_sync_status":
            return "☁️ Checking iCloud sync status... Head to Settings → iCloud Sync to see the latest details."
        case "sync_now":
            return "☁️ Manual sync triggered! Your data is being pushed to iCloud now."
        case "toggle_icloud_sync":
            return "☁️ You can toggle iCloud sync in Settings → iCloud Sync. This keeps your jokes, sets, and recordings synced across all your devices."
            
        // ═══════════════════════════════════════════
        // SETTINGS
        // ═══════════════════════════════════════════
        case "export_all_jokes":
            return "📤 Export ready! Head to Settings → Export to download your entire joke collection as a backup."
        case "export_recordings":
            return "📤 Recording export available in Settings. You can back up all your set audio."
        case "clear_cache":
            return "🧹 Cache cleared! The app should feel lighter now. No data was lost — just temporary files."
            
        // ═══════════════════════════════════════════
        // HELP
        // ═══════════════════════════════════════════
        case "open_help_faq":
            return "❓ Opening Help & FAQ! You'll find guides for every feature in the app."
        case "explain_feature":
            return buildFeatureExplanation(from: message)
            
        default:
            return buildHelpResponse(for: dataContext)
        }
    }
    
    // MARK: - Feature Explanations
    
    private func buildFeatureExplanation(from message: String) -> String {
        let lower = message.lowercased()
        
        if lower.contains("gaggrabber") || lower.contains("import") {
            return """
            📥 **GagGrabber** is BitBinder's smart import tool.
            • Import jokes from PDFs, text files, or photos.
            • Automatically extracts individual jokes from your documents.
            • Review each one before it's saved to your collection.
            • There's a daily extraction limit that resets every 24 hours.
            """
        }
        if lower.contains("roast") {
            return """
            🔥 **Roast Mode** transforms BitBinder into a roast battle prep tool.
            • Create targets with names and photos.
            • Write and organize burns under each target.
            • Build roast set lists for battle night.
            • Present mode shows one burn at a time on stage.
            """
        }
        if lower.contains("hits") || lower.contains("hit") {
            return """
            ⭐ **The Hits** is your collection of proven material.
            • Mark any joke as a "Hit" when it consistently works on stage.
            • Use The Hits to quickly build strong set lists.
            • It's your highlight reel of tested material.
            """
        }
        if lower.contains("set list") || lower.contains("sets") {
            return """
            📋 **Set Lists** help you plan your stage time.
            • Create named sets for different venues or time slots.
            • Drag to reorder jokes in your lineup.
            • Estimate total runtime.
            • Present mode shows one joke at a time on stage.
            """
        }
        if lower.contains("bitbuddy") || lower.contains("commands") {
            return """
            🤖 **BitBuddy** is your comedy writing partner.
            • Analyze jokes for structure and strengths.
            • Get rewrites, premises, and new joke ideas.
            • Summarize your comedy style.
            • Find gaps in your material.
            Just type naturally — I understand \(BitBuddyIntentRouter.shared.allIntents.count) different commands across \(BitBuddySection.allCases.count) app sections.
            """
        }
        if lower.contains("brainstorm") {
            return """
            💡 **Brainstorm** is your sticky note wall for raw ideas.
            • Capture ideas as text or voice.
            • Group by topic to find patterns.
            • Promote ideas to full jokes when ready.
            """
        }
        if lower.contains("icloud") || lower.contains("sync") {
            return """
            ☁️ **iCloud Sync** keeps your data safe across devices.
            • Toggle sync in Settings.
            • Force a manual sync anytime.
            • All jokes, sets, recordings, and notes stay in sync.
            """
        }
        if lower.contains("recording") {
            return """
            🎙️ **Recordings** let you capture and review your sets.
            • Record audio of your performances.
            • Transcribe recordings to searchable text.
            • Clip and trim the best moments.
            • Attach recordings to set lists for post-show review.
            """
        }
        if lower.contains("notebook") {
            return """
            📓 **Notebook** is your freeform scratch pad.
            • Quick text capture — no formatting needed.
            • Attach photos for visual inspiration.
            • Search across all your notes.
            """
        }
        
        return "I can explain any feature! Try asking about GagGrabber, Roast Mode, The Hits, Set Lists, Brainstorm, Recordings, Notebook, iCloud Sync, or BitBuddy commands."
    }
    
    // MARK: - Help Response Builder
    
    private func buildHelpResponse(for dataContext: BitBuddyDataContext) -> String {
        let userName = dataContext.userName
        return """
        Hey \(userName)! I didn't quite catch that. Here's what I can do:
        
        🎭 **Jokes**: save, edit, tag, search, share, organize into folders
        💡 **Brainstorm**: capture ideas, voice notes, promote to jokes
        📋 **Set Lists**: create, reorder, shuffle, estimate time, present
        🎙️ **Recordings**: record, play, transcribe, clip, attach to sets
        🤖 **Writing Help**: analyze, improve, punch up, generate premises, crowdwork
        📓 **Notebook**: save notes, attach photos, search
        🔥 **Roast Mode**: targets, burns, roast sets, battle prep
        📥 **Import**: PDF/image import, review queue, daily limits
        ☁️ **Sync**: iCloud status, manual sync, toggle
        ⚙️ **Settings**: export, clear cache
        ❓ **Help**: explain any feature
        
        Try something like: "analyze this joke" or "create a set list for tonight"
        """
    }
    
    // MARK: - Handlers
    
    private func analyze(_ text: String) -> String {
        guard !text.isEmpty else { return "Please provide text to analyze." }
        
        let structure = JokeAnalyzer.structure(text)
        // Detect strengths based on structure and content
        var strengths: [String] = []
        if structure != .unknown { strengths.append(structure.rawValue) }
        
        if let topic = JokeAnalyzer.detectTopic(text) {
             strengths.append("clear topic (\(topic))")
        }
        
        // Detect twist/reversal patterns in the joke
        let twistPatterns = [
            "\\bbut\\b", "\\bactually\\b", "\\bturns out\\b", "\\bplot twist\\b",
            "\\binstead\\b", "\\bexcept\\b", "\\bunless\\b", "\\buntil\\b",
            "\\blittle did\\b", "\\bnot really\\b", "\\bjust kidding\\b",
            "\\bsurprise\\b", "\\bthe real\\b", "\\bnope\\b"
        ]
        let lower = text.lowercased()
        let twistCount = twistPatterns.filter { lower.range(of: $0, options: .regularExpression) != nil }.count
        if twistCount >= 1 { strengths.append("twist") }
        if twistCount >= 2 { strengths.append("double reversal") }
        
        if strengths.isEmpty { strengths.append("concise") }

        let suggestions = JokeAnalyzer.suggestEdits(text)
        
        var response = "Structure: \(structure.rawValue).\n"
        response += "Strengths: \(strengths.joined(separator: ", ")).\n"
        
        if !suggestions.isEmpty {
           response += "Edits:\n\(suggestions.joined(separator: "\n"))"
        } else {
           response += "Edits: None specific found."
        }
        
        return response
    }
    
    private func improve(_ text: String) -> String {
        guard !text.isEmpty else { return "Please provide a joke to improve." }
        let suggestions = JokeAnalyzer.suggestEdits(text)
        
        if suggestions.isEmpty {
             return """
             • Tighten setup: Remove context not needed for the punchline.
             • Swap punchline: Try ending on a harder consonant sound.
             """
        }
        return suggestions.map { "• \($0)" }.joined(separator: "\n")
    }
    
    private func premise(_ topic: String) -> String {
        let actualTopic = topic.isEmpty ? (userProfile.topTopics.max(by: { $0.value < $1.value })?.key ?? "dating") : topic
        return "What if \(actualTopic) implied something totally different about us? (Example: \(actualTopic) is actually just adult hide and seek.)"
    }

    private func generate(_ topic: String) -> String {
        let actualTopic = topic.isEmpty ? (userProfile.topTopics.max(by: { $0.value < $1.value })?.key ?? "work") : topic
        let template = BitBuddyResources.templates.randomElement() ?? "I thought [Topic] was [expectation], but it turns out it's more like [reality]."

        // Build contextual substitution pools
        let relations = ["mom", "dad", "roommate", "ex", "coworker", "therapist", "barista", "dentist"]
        let objects = ["toaster", "smoke alarm", "GPS", "printer", "parking meter", "ikea manual"]
        let activities = ["meal prepping", "meditating", "running", "online dating", "networking", "budgeting"]
        let analogies = ["assembling IKEA furniture blindfolded", "explaining WiFi to my grandma", "defusing a bomb in a sitcom", "parallel parking a bus"]
        let adjectives = ["old", "broke", "tired", "addicted to your phone", "avoiding people", "out of shape"]
        let actions = ["google your symptoms", "set five alarms", "eat cereal for dinner", "rehearse conversations in the shower"]
        let traits = ["chaotic", "expensive", "exhausting", "overhyped"]
        let opposites = ["boring", "free", "relaxing", "underrated"]
        let twists = ["extra steps", "guilt", "a monthly fee", "strangers judging you"]
        let expectations = ["simple", "fun", "relaxing", "straightforward"]
        let realities = ["a trap", "a scam with good branding", "just organized suffering", "anxiety with extra steps"]
        let reasons = ["nobody reads the instructions", "we peaked in 2012", "the universe is petty", "capitalism"]
        let groups = ["adults", "millennials", "morning people", "gym bros", "landlords", "coworkers"]

        // Pick a second topic that's different from the main one
        let otherTopic = BitBuddyResources.topics.filter { $0 != actualTopic }.randomElement() ?? "taxes"

        var joke = template
        joke = joke.replacingOccurrences(of: "[Topic]", with: actualTopic)
        joke = joke.replacingOccurrences(of: "[Topic A]", with: actualTopic)
        joke = joke.replacingOccurrences(of: "[Topic B]", with: otherTopic)
        joke = joke.replacingOccurrences(of: "[Other Topic]", with: otherTopic)
        joke = joke.replacingOccurrences(of: "[Group]", with: groups.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Action]", with: actions.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Reason]", with: reasons.randomElement()!)
        joke = joke.replacingOccurrences(of: "[expectation]", with: expectations.randomElement()!)
        joke = joke.replacingOccurrences(of: "[reality]", with: realities.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Twist]", with: twists.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Adjective]", with: adjectives.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Relation]", with: relations.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Object]", with: objects.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Comparison]", with: analogies.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Activity]", with: activities.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Analogy]", with: analogies.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Trait]", with: traits.randomElement()!)
        joke = joke.replacingOccurrences(of: "[Opposite Trait]", with: opposites.randomElement()!)

        return joke
    }

    private func style() -> String {
        return userProfile.summary.isEmpty ? "Not enough data to determine style." : userProfile.summary
    }

    private func suggestTopic() -> String {
        // Pick a topic NOT in top topics
        let usedTopics = Set(userProfile.topTopics.keys)
        // Filter BitBuddyResources.topics
        let newTopics = BitBuddyResources.topics.filter { !usedTopics.contains($0) }
        let suggestion = newTopics.randomElement() ?? "quantum physics"
        
        return "\(suggestion.capitalized) (unused). Try: \"Why is \(suggestion) so hard to explain? Because...\""
    }

    // MARK: - Helpers
    
    private func inferTagsFromContent(_ text: String) -> [String] {
        let lower = text.lowercased()
        let candidatePairs: [(String, String)] = [
            ("dating", "dating"), ("relationship", "relationships"), ("work", "work"),
            ("family", "family"), ("travel", "travel"), ("airport", "travel"),
            ("tech", "tech"), ("phone", "tech"), ("gym", "fitness"),
            ("therapy", "personal"), ("money", "money"), ("food", "food"),
            ("uber", "rideshare"), ("landlord", "housing"), ("subway", "transit"),
            ("tinder", "dating"), ("marriage", "relationships"), ("politics", "politics"),
            ("drunk", "nightlife"), ("doctor", "health"), ("school", "education"),
            ("crowd", "crowdwork"), ("roast", "roast"), ("dark", "dark humor")
        ]
        let tags = candidatePairs.compactMap { lower.contains($0.0) ? $0.1 : nil }
        return Array(Set(tags)).sorted().prefix(5).map { $0 }
    }
    
    private func updateProfile(from summaries: [BitBuddyJokeSummary]) {
        var profile = UserStyleProfile()
        guard !summaries.isEmpty else {
            self.userProfile = profile
            return
        }
        
        var totalWords = 0
        var totalChars = 0
        var topicCounts: [String: Int] = [:]
        var structureCounts: [String: Int] = [:]
        
        for joke in summaries {
            totalWords += joke.content.split(separator: " ").count
            totalChars += joke.content.count
            
            if let topic = JokeAnalyzer.detectTopic(joke.content) {
                topicCounts[topic, default: 0] += 1
            }
            
            let structure = JokeAnalyzer.structure(joke.content)
            structureCounts[structure.rawValue, default: 0] += 1
        }
        
        profile.avgWordCount = Double(totalWords) / Double(summaries.count)
        profile.avgCharCount = Double(totalChars) / Double(summaries.count)
        profile.topTopics = topicCounts
        profile.structureDistribution = structureCounts
        
        self.userProfile = profile
    }
    
    private func extractContent(from message: String, prefix: String) -> String {
        var content = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        if content.starts(with: ":") {
            content = content.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return content
    }
}
