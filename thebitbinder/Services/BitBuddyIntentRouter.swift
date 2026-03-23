//
//  BitBuddyIntentRouter.swift
//  thebitbinder
//
//  Intent routing engine for BitBuddy v2.0.
//  Maps natural-language user messages to one of 93 intents
//  across 11 app sections. Supports fuzzy keyword matching,
//  section routing, and structured action dispatch.
//

import Foundation

// MARK: - App Section

/// Every section BitBuddy can route an intent to.
enum BitBuddySection: String, CaseIterable, Codable, Sendable {
    case jokes
    case brainstorm
    case setLists    = "set_lists"
    case recordings
    case bitbuddy
    case notebook
    case roastMode   = "roast_mode"
    case importFlow  = "import"
    case sync
    case settings
    case help

    var displayName: String {
        switch self {
        case .jokes:      return "Jokes"
        case .brainstorm: return "Brainstorm"
        case .setLists:   return "Set Lists"
        case .recordings: return "Recordings"
        case .bitbuddy:   return "BitBuddy"
        case .notebook:   return "Notebook"
        case .roastMode:  return "Roast Mode"
        case .importFlow: return "GagGrabber Import"
        case .sync:       return "iCloud Sync"
        case .settings:   return "Settings"
        case .help:       return "Help & FAQ"
        }
    }
}

// MARK: - Intent Category

enum BitBuddyIntentCategory: String, Codable, Sendable {
    case capture
    case edit
    case manage
    case organize
    case search
    case export
    case convert
    case analysis
    case generation
    case present
    case playback
    case transcription
    case review
    case status
    case action
    case settings
    case navigation
    case help
}

// MARK: - Intent Definition

/// A single intent BitBuddy can recognise.
struct BitBuddyIntent: Sendable, Identifiable {
    let id: String               // e.g. "save_joke"
    let section: BitBuddySection
    let category: BitBuddyIntentCategory
    let description: String
    let keywords: [String]       // quick match tokens
    let examplePatterns: [String] // full example phrases

    /// Returns true when `text` fuzzy-matches this intent.
    func matches(_ text: String) -> Double {
        let lower = text.lowercased()
        var score: Double = 0

        // Keyword hits
        for keyword in keywords {
            if lower.contains(keyword) { score += 1.0 }
        }

        // Example-phrase partial match (best substring overlap)
        for example in examplePatterns {
            let exLower = example.lowercased()
            if lower == exLower { score += 10.0; continue }
            if lower.contains(exLower) || exLower.contains(lower) { score += 3.0; continue }
            // Token overlap
            let exTokens = Set(exLower.split(separator: " ").map(String.init))
            let inTokens = Set(lower.split(separator: " ").map(String.init))
            let overlap = Double(exTokens.intersection(inTokens).count) / Double(max(exTokens.count, 1))
            if overlap > 0.5 { score += overlap * 2.0 }
        }

        return score
    }
}

// MARK: - Router Result

struct BitBuddyRouteResult: Sendable {
    let intent: BitBuddyIntent
    let confidence: Double          // 0…1 (normalised)
    let section: BitBuddySection
    let category: BitBuddyIntentCategory
    let extractedEntities: [String: String]  // e.g. "title", "folder", "target"
}

// MARK: - Intent Router

/// Central router that classifies freeform text into structured intents.
final class BitBuddyIntentRouter: @unchecked Sendable {
    static let shared = BitBuddyIntentRouter()

    let allIntents: [BitBuddyIntent]

    private init() {
        self.allIntents = Self.buildIntentCatalog()
    }

    // MARK: - Public API

    /// Find the best-matching intent for a user message.
    /// Returns `nil` when no intent scores above the threshold.
    func route(_ message: String) -> BitBuddyRouteResult? {
        let scored = allIntents.map { intent -> (BitBuddyIntent, Double) in
            (intent, intent.matches(message))
        }
        .sorted { $0.1 > $1.1 }

        guard let best = scored.first, best.1 > 1.0 else { return nil }

        let maxPossible = max(best.1, 1.0)
        let confidence = min(best.1 / max(maxPossible, 10.0), 1.0)

        let entities = extractEntities(from: message, intent: best.0)

        return BitBuddyRouteResult(
            intent: best.0,
            confidence: confidence,
            section: best.0.section,
            category: best.0.category,
            extractedEntities: entities
        )
    }

    /// Return top-N matching intents (useful for disambiguation).
    func topMatches(_ message: String, limit: Int = 3) -> [BitBuddyRouteResult] {
        allIntents
            .map { ($0, $0.matches(message)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .filter { $0.1 > 0.5 }
            .map { pair in
                BitBuddyRouteResult(
                    intent: pair.0,
                    confidence: min(pair.1 / 10.0, 1.0),
                    section: pair.0.section,
                    category: pair.0.category,
                    extractedEntities: extractEntities(from: message, intent: pair.0)
                )
            }
    }

    /// All intents for a given section.
    func intents(for section: BitBuddySection) -> [BitBuddyIntent] {
        allIntents.filter { $0.section == section }
    }

    // MARK: - Entity Extraction (lightweight)

    private func extractEntities(from message: String, intent: BitBuddyIntent) -> [String: String] {
        var entities: [String: String] = [:]
        let lower = message.lowercased()

        // Extract text after common prepositions for context
        let prepositions = ["called", "named", "titled", "to", "into", "from", "about", "for", "in", "under"]
        for prep in prepositions {
            if let range = lower.range(of: " \(prep) ") {
                let after = String(message[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty {
                    // Map to most likely entity for this intent
                    switch intent.section {
                    case .jokes:
                        if prep == "to" || prep == "into" || prep == "in" || prep == "under" {
                            entities["folder"] = after
                        } else {
                            entities["title"] = after
                        }
                    case .setLists:
                        entities["set_name"] = after
                    case .roastMode:
                        entities["target"] = after
                    case .recordings:
                        entities["recording_name"] = after
                    default:
                        entities["value"] = after
                    }
                    break
                }
            }
        }

        // Extract quoted strings as explicit entity values
        let quotePattern = try? NSRegularExpression(pattern: #""([^"]+)""#)
        let nsString = message as NSString
        if let match = quotePattern?.firstMatch(in: message, range: NSRange(location: 0, length: nsString.length)) {
            let quoted = nsString.substring(with: match.range(at: 1))
            entities["quoted_value"] = quoted
        }

        return entities
    }

    // MARK: - Intent Catalog (93 intents)

    // swiftlint:disable function_body_length
    private static func buildIntentCatalog() -> [BitBuddyIntent] {
        [
            // ═══════════════════════════════════════════
            // SECTION: JOKES (21 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "save_joke",
                section: .jokes, category: .capture,
                description: "Save a new joke or bit to the Jokes section.",
                keywords: ["save", "joke", "add", "bit", "store", "create", "put"],
                examplePatterns: [
                    "save this joke", "add this bit to my jokes", "put this in my joke book",
                    "create a new joke from this idea", "store this as a joke",
                    "save this under jokes", "add a joke", "make this a saved bit"
                ]
            ),
            BitBuddyIntent(
                id: "save_joke_in_folder",
                section: .jokes, category: .capture,
                description: "Save a joke directly into a folder.",
                keywords: ["save", "joke", "folder", "into", "under", "file"],
                examplePatterns: [
                    "save this joke to", "add this bit into my folder",
                    "put this joke in", "create this joke inside",
                    "store this under", "drop this bit into",
                    "save this in the folder", "file this joke under"
                ]
            ),
            BitBuddyIntent(
                id: "edit_joke",
                section: .jokes, category: .edit,
                description: "Edit an existing joke.",
                keywords: ["edit", "update", "change", "rewrite", "fix", "replace", "shorten", "clean"],
                examplePatterns: [
                    "edit my joke", "update the wording", "change the second line",
                    "rewrite the setup", "fix the phrasing", "replace the punchline",
                    "shorten this joke", "clean up this wording"
                ]
            ),
            BitBuddyIntent(
                id: "rename_joke",
                section: .jokes, category: .edit,
                description: "Rename a saved joke.",
                keywords: ["rename", "retitle", "title", "name"],
                examplePatterns: [
                    "rename this joke", "change the title of this bit",
                    "retitle this joke", "give this joke a better name",
                    "update the joke title", "call this bit"
                ]
            ),
            BitBuddyIntent(
                id: "delete_joke",
                section: .jokes, category: .manage,
                description: "Delete or trash a joke.",
                keywords: ["delete", "remove", "trash", "get rid", "throw away"],
                examplePatterns: [
                    "delete this joke", "remove this bit", "trash the joke",
                    "get rid of this joke", "take this out of my joke book",
                    "remove this from jokes", "throw away this bit"
                ]
            ),
            BitBuddyIntent(
                id: "restore_deleted_joke",
                section: .jokes, category: .manage,
                description: "Restore a deleted joke.",
                keywords: ["restore", "bring back", "undo", "recover", "undelete"],
                examplePatterns: [
                    "restore the joke I deleted", "bring back", "undo that delete",
                    "recover my deleted bit", "restore this joke from trash",
                    "put that joke back", "recover"
                ]
            ),
            BitBuddyIntent(
                id: "mark_hit",
                section: .jokes, category: .organize,
                description: "Mark a joke as a hit.",
                keywords: ["hit", "star", "favorite", "best", "proven", "mark"],
                examplePatterns: [
                    "mark this as a hit", "star this joke", "add this to the hits",
                    "this joke works mark it", "favorite this bit", "make this one a hit",
                    "tag this as proven", "put this in my best jokes"
                ]
            ),
            BitBuddyIntent(
                id: "unmark_hit",
                section: .jokes, category: .organize,
                description: "Remove hit status from a joke.",
                keywords: ["unstar", "unfavorite", "remove hit", "clear hit", "unmark"],
                examplePatterns: [
                    "unstar this joke", "take this out of the hits",
                    "remove the hit marker", "not a hit anymore",
                    "unfavorite this joke", "clear the hit status"
                ]
            ),
            BitBuddyIntent(
                id: "add_tags",
                section: .jokes, category: .organize,
                description: "Add tags to a joke.",
                keywords: ["tag", "label", "mark", "category"],
                examplePatterns: [
                    "tag this joke", "add tags", "mark this bit as",
                    "tag this with", "give this joke better tags",
                    "label this joke", "add category tags"
                ]
            ),
            BitBuddyIntent(
                id: "remove_tags",
                section: .jokes, category: .organize,
                description: "Remove tags from a joke.",
                keywords: ["remove tag", "take off tag", "delete tag", "clear tag", "unlabel", "drop tag"],
                examplePatterns: [
                    "remove the tag", "take off the tag", "delete the tags on this joke",
                    "clear the tags", "unlabel this joke", "drop the tag"
                ]
            ),
            BitBuddyIntent(
                id: "move_joke_folder",
                section: .jokes, category: .organize,
                description: "Move a joke between folders.",
                keywords: ["move", "refile", "switch folder", "transfer"],
                examplePatterns: [
                    "move this joke to", "put into", "move this bit out of",
                    "refile this joke", "switch this bit to a different folder",
                    "move this to my new material", "transfer this joke"
                ]
            ),
            BitBuddyIntent(
                id: "create_folder",
                section: .jokes, category: .organize,
                description: "Create a joke folder.",
                keywords: ["create folder", "make folder", "new folder", "add folder", "start folder"],
                examplePatterns: [
                    "create a folder", "make a new joke folder",
                    "add a folder for", "start a folder named",
                    "create a category folder", "make me a new folder"
                ]
            ),
            BitBuddyIntent(
                id: "rename_folder",
                section: .jokes, category: .organize,
                description: "Rename a joke folder.",
                keywords: ["rename folder", "retitle folder", "change folder name"],
                examplePatterns: [
                    "rename this folder", "change the folder name",
                    "retitle my jokes folder", "call this folder",
                    "update the name of this folder", "give this folder a better name"
                ]
            ),
            BitBuddyIntent(
                id: "delete_folder",
                section: .jokes, category: .organize,
                description: "Delete a joke folder.",
                keywords: ["delete folder", "remove folder", "trash folder", "erase folder"],
                examplePatterns: [
                    "delete this folder", "remove the folder", "get rid of this joke folder",
                    "trash this category", "remove this folder from jokes", "erase the folder"
                ]
            ),
            BitBuddyIntent(
                id: "search_jokes",
                section: .jokes, category: .search,
                description: "Search jokes by keyword, title, or content.",
                keywords: ["find", "search", "show", "look for", "pull up"],
                examplePatterns: [
                    "find jokes about", "search my jokes for", "show me bits with",
                    "look for the joke about", "find any joke that mentions",
                    "search all my jokes", "pull up jokes"
                ]
            ),
            BitBuddyIntent(
                id: "filter_jokes_recent",
                section: .jokes, category: .search,
                description: "Show recently created or modified jokes.",
                keywords: ["recent", "newest", "latest", "this week", "today", "lately"],
                examplePatterns: [
                    "show my recent jokes", "what did I write this week",
                    "pull up my newest bits", "show jokes I edited today",
                    "show my latest material", "what have I written lately"
                ]
            ),
            BitBuddyIntent(
                id: "filter_jokes_by_folder",
                section: .jokes, category: .search,
                description: "Filter jokes by folder.",
                keywords: ["folder", "filter by folder", "show folder", "open folder"],
                examplePatterns: [
                    "show me the jokes in", "open my folder",
                    "only show bits from", "filter jokes by",
                    "show the folder", "pull up everything in", "view jokes filed under"
                ]
            ),
            BitBuddyIntent(
                id: "filter_jokes_by_tag",
                section: .jokes, category: .search,
                description: "Filter jokes by tag.",
                keywords: ["filter by tag", "tagged", "show tagged", "filter tag"],
                examplePatterns: [
                    "show me all my dating jokes", "filter jokes by",
                    "only show observational bits", "pull up everything tagged",
                    "show bits tagged", "find all jokes marked"
                ]
            ),
            BitBuddyIntent(
                id: "list_hits",
                section: .jokes, category: .search,
                description: "Show all jokes marked as hits.",
                keywords: ["hits", "best jokes", "starred", "favorites", "proven", "strongest"],
                examplePatterns: [
                    "show me the hits", "list my best jokes", "pull up all starred jokes",
                    "show the jokes that work", "open my hit list",
                    "show proven material", "give me my strongest jokes"
                ]
            ),
            BitBuddyIntent(
                id: "share_joke",
                section: .jokes, category: .export,
                description: "Share a joke externally.",
                keywords: ["share", "export", "send", "copy"],
                examplePatterns: [
                    "share this joke", "export this bit", "send this joke out",
                    "make this joke shareable", "copy this joke for me",
                    "prepare this bit to share"
                ]
            ),
            BitBuddyIntent(
                id: "duplicate_joke",
                section: .jokes, category: .manage,
                description: "Duplicate an existing joke.",
                keywords: ["duplicate", "clone", "copy", "another version"],
                examplePatterns: [
                    "duplicate this joke", "make a copy of this bit",
                    "clone", "copy this joke into a new entry",
                    "create a duplicate", "make another version"
                ]
            ),
            BitBuddyIntent(
                id: "merge_jokes",
                section: .jokes, category: .edit,
                description: "Combine two joke drafts.",
                keywords: ["merge", "combine", "put together", "blend"],
                examplePatterns: [
                    "merge these two jokes", "combine this bit with",
                    "put these versions together", "make one joke out of these",
                    "combine both drafts", "blend these bits into one"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: BRAINSTORM (7 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "add_brainstorm_note",
                section: .brainstorm, category: .capture,
                description: "Create a brainstorm sticky note.",
                keywords: ["brainstorm", "idea", "sticky", "note", "thought", "capture"],
                examplePatterns: [
                    "add this to brainstorm", "make a new brainstorm note",
                    "save this idea as a sticky note", "throw this in brainstorm",
                    "capture this thought", "make a brainstorm card",
                    "add an idea card", "save this as an idea"
                ]
            ),
            BitBuddyIntent(
                id: "voice_capture_idea",
                section: .brainstorm, category: .capture,
                description: "Capture a brainstorm note from voice.",
                keywords: ["voice", "mic", "speech", "transcribe", "record idea"],
                examplePatterns: [
                    "start voice capture", "record an idea with the mic",
                    "let me say this out loud and save it", "open mic capture for brainstorm",
                    "transcribe this thought into brainstorm", "save a voice idea",
                    "start a speech-to-text brainstorm note", "use the mic for this idea"
                ]
            ),
            BitBuddyIntent(
                id: "edit_brainstorm_note",
                section: .brainstorm, category: .edit,
                description: "Edit a brainstorm note.",
                keywords: ["edit brainstorm", "change idea", "update idea", "fix brainstorm", "rewrite sticky"],
                examplePatterns: [
                    "edit this brainstorm note", "change the wording on this idea card",
                    "update this idea", "fix this brainstorm note",
                    "rewrite this sticky note", "shorten this brainstorm card",
                    "clean up this idea", "edit the note I just made"
                ]
            ),
            BitBuddyIntent(
                id: "delete_brainstorm_note",
                section: .brainstorm, category: .manage,
                description: "Delete a brainstorm note.",
                keywords: ["delete brainstorm", "remove idea", "trash brainstorm", "erase idea"],
                examplePatterns: [
                    "delete this brainstorm note", "remove this idea card",
                    "trash this brainstorm idea", "delete this sticky note",
                    "get rid of this idea", "remove this thought",
                    "erase this brainstorm card", "delete the note I just made"
                ]
            ),
            BitBuddyIntent(
                id: "promote_idea_to_joke",
                section: .brainstorm, category: .convert,
                description: "Convert a brainstorm idea into a joke.",
                keywords: ["promote", "convert", "turn into joke", "make joke", "move to jokes"],
                examplePatterns: [
                    "turn this idea into a joke", "promote this brainstorm note to jokes",
                    "make this sticky note a full joke", "convert this idea card into a bit",
                    "save this brainstorm as a joke", "move this idea into jokes",
                    "turn this into a proper bit", "make a joke out of this note"
                ]
            ),
            BitBuddyIntent(
                id: "search_brainstorm",
                section: .brainstorm, category: .search,
                description: "Search brainstorm notes.",
                keywords: ["search brainstorm", "find idea", "find note", "look for idea"],
                examplePatterns: [
                    "find brainstorm notes about", "search my idea cards for",
                    "look for the sticky note about", "show brainstorm notes with",
                    "find that random idea about", "search brainstorm for",
                    "pull up notes that mention", "find ideas about"
                ]
            ),
            BitBuddyIntent(
                id: "group_brainstorm_topics",
                section: .brainstorm, category: .organize,
                description: "Group brainstorm notes by topic or theme.",
                keywords: ["group", "cluster", "organize", "sort", "bundle", "categorize"],
                examplePatterns: [
                    "group these ideas by topic", "cluster my brainstorm notes",
                    "organize these idea cards by theme", "group my brainstorm by subject",
                    "sort these thoughts into categories", "bundle related brainstorm notes",
                    "show me which ideas go together", "organize this brainstorm mess"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: SET LISTS (12 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "create_set_list",
                section: .setLists, category: .capture,
                description: "Create a new set list.",
                keywords: ["create set", "make set", "new set", "build set", "start set"],
                examplePatterns: [
                    "create a new set list", "make a set list for tonight",
                    "start a set called", "build me a new set list",
                    "create a performance set", "make a set for the club spot",
                    "start a list for open mic material", "new set list"
                ]
            ),
            BitBuddyIntent(
                id: "rename_set_list",
                section: .setLists, category: .edit,
                description: "Rename a set list.",
                keywords: ["rename set", "retitle set", "change set name"],
                examplePatterns: [
                    "rename this set list", "change the set list name",
                    "retitle this set", "call this set",
                    "update the name of this set list", "give this set a better title"
                ]
            ),
            BitBuddyIntent(
                id: "delete_set_list",
                section: .setLists, category: .manage,
                description: "Delete a set list.",
                keywords: ["delete set", "remove set", "trash set", "erase set"],
                examplePatterns: [
                    "delete this set list", "remove this set",
                    "trash the set called", "get rid of this performance list",
                    "delete my open mic set", "remove this set from the app"
                ]
            ),
            BitBuddyIntent(
                id: "add_joke_to_set",
                section: .setLists, category: .edit,
                description: "Add jokes to a set list.",
                keywords: ["add to set", "put in set", "include in set", "drop into set"],
                examplePatterns: [
                    "add this joke to my set", "put into",
                    "add three jokes to tonight's set", "include this bit in the set list",
                    "put this in my opener slot", "add jokes to this set",
                    "drop this bit into", "add this joke to the lineup"
                ]
            ),
            BitBuddyIntent(
                id: "remove_joke_from_set",
                section: .setLists, category: .edit,
                description: "Remove a joke from a set list.",
                keywords: ["remove from set", "take out of set", "delete from set", "pull from set", "cut from set"],
                examplePatterns: [
                    "remove this joke from the set", "take out of",
                    "delete this bit from the lineup", "pull this joke from tonight's set",
                    "remove this from the running order", "take this bit out of the set list",
                    "cut from the set", "remove this slot"
                ]
            ),
            BitBuddyIntent(
                id: "reorder_set",
                section: .setLists, category: .edit,
                description: "Reorder the jokes in a set list.",
                keywords: ["reorder", "move higher", "move lower", "opener", "closer", "switch", "running order"],
                examplePatterns: [
                    "move this joke higher in the set", "make this my opener",
                    "put this bit third", "move the closer to the end",
                    "reorder this set list", "switch these two jokes",
                    "put the strong joke up front", "change the running order"
                ]
            ),
            BitBuddyIntent(
                id: "estimate_set_time",
                section: .setLists, category: .analysis,
                description: "Estimate set duration.",
                keywords: ["how long", "estimate", "runtime", "minutes", "length", "stage time", "duration"],
                examplePatterns: [
                    "how long is this set", "estimate the runtime of this set list",
                    "how many minutes is tonight's set", "tell me the approximate length",
                    "calculate this set time", "how long would this material run",
                    "estimate stage time for this set", "give me the total minutes"
                ]
            ),
            BitBuddyIntent(
                id: "shuffle_set",
                section: .setLists, category: .edit,
                description: "Shuffle a set list.",
                keywords: ["shuffle", "randomize", "mix up", "scramble"],
                examplePatterns: [
                    "shuffle this set", "randomize the joke order",
                    "mix up this set list", "scramble the running order",
                    "give me a shuffled version", "randomize tonight's set"
                ]
            ),
            BitBuddyIntent(
                id: "suggest_set_opener",
                section: .setLists, category: .analysis,
                description: "Suggest an opener for a set.",
                keywords: ["opener", "open", "first joke", "opening bit"],
                examplePatterns: [
                    "what should open this set", "pick my opener",
                    "which joke should go first", "find the best opening bit",
                    "suggest a strong opener", "choose the opening joke",
                    "what is the best first joke", "help me open strong"
                ]
            ),
            BitBuddyIntent(
                id: "suggest_set_closer",
                section: .setLists, category: .analysis,
                description: "Suggest a closer for a set.",
                keywords: ["closer", "close", "end", "final joke", "closing bit", "land"],
                examplePatterns: [
                    "what should close this set", "pick my closer",
                    "which joke should end the set", "find the best closing bit",
                    "suggest a strong closer", "choose the final joke",
                    "what should I end on", "help me land this set"
                ]
            ),
            BitBuddyIntent(
                id: "present_set",
                section: .setLists, category: .present,
                description: "Enter presentation mode for a set list.",
                keywords: ["present", "performance mode", "presenter view", "stage version"],
                examplePatterns: [
                    "present this set", "open performance mode",
                    "show this set in presenter view", "give me the stage version",
                    "start presenting this set", "open the set for performance",
                    "go into set presentation mode", "present the lineup"
                ]
            ),
            BitBuddyIntent(
                id: "find_set_list",
                section: .setLists, category: .search,
                description: "Find set lists by name or content.",
                keywords: ["find set", "search set", "show set", "pull up set"],
                examplePatterns: [
                    "find my set list for", "search set lists for",
                    "show me the set I made for", "find a set called",
                    "pull up my open mic set", "search my set lists",
                    "find the ten minute set", "show sets that include"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: RECORDINGS (10 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "start_recording",
                section: .recordings, category: .capture,
                description: "Start an audio recording.",
                keywords: ["start recording", "record", "begin recording", "hit record", "open recorder"],
                examplePatterns: [
                    "start recording", "record my set", "begin a new recording",
                    "open the recorder", "start an audio file for this set",
                    "hit record", "record this performance", "begin recording now"
                ]
            ),
            BitBuddyIntent(
                id: "stop_recording",
                section: .recordings, category: .capture,
                description: "Stop an audio recording.",
                keywords: ["stop recording", "end recording", "finish recording", "done recording", "cut recording"],
                examplePatterns: [
                    "stop recording", "end the recording", "finish this audio file",
                    "stop the recorder", "done recording", "end this set recording",
                    "save and stop recording", "cut the recording"
                ]
            ),
            BitBuddyIntent(
                id: "rename_recording",
                section: .recordings, category: .edit,
                description: "Rename a recording.",
                keywords: ["rename recording", "retitle recording", "change recording title"],
                examplePatterns: [
                    "rename this recording", "call this recording",
                    "change the title of this audio file", "retitle this set recording",
                    "rename the recording from tonight", "update this recording name"
                ]
            ),
            BitBuddyIntent(
                id: "delete_recording",
                section: .recordings, category: .manage,
                description: "Delete a recording.",
                keywords: ["delete recording", "remove recording", "trash recording", "erase audio"],
                examplePatterns: [
                    "delete this recording", "remove this audio file",
                    "trash the recording from tonight", "delete the set recording",
                    "get rid of this recording", "remove this from recordings", "erase this audio"
                ]
            ),
            BitBuddyIntent(
                id: "play_recording",
                section: .recordings, category: .playback,
                description: "Play back a recording.",
                keywords: ["play", "listen", "playback", "start audio"],
                examplePatterns: [
                    "play this recording", "start the audio", "listen to my set",
                    "play the set recording", "open playback",
                    "start this audio file", "play the recording from tonight", "listen back"
                ]
            ),
            BitBuddyIntent(
                id: "transcribe_recording",
                section: .recordings, category: .transcription,
                description: "Transcribe a recording.",
                keywords: ["transcribe", "transcript", "turn audio into text", "speech to text"],
                examplePatterns: [
                    "transcribe this recording", "make a transcript of my set",
                    "turn this audio into text", "create a transcript",
                    "transcribe the recording from tonight", "convert this set recording to text",
                    "give me the transcript", "run transcription"
                ]
            ),
            BitBuddyIntent(
                id: "search_transcripts",
                section: .recordings, category: .search,
                description: "Search transcripts.",
                keywords: ["search transcript", "find in transcript", "search recording text"],
                examplePatterns: [
                    "search my transcripts for", "find the set where I talked about",
                    "look through recordings for", "search the transcript text",
                    "find any recording mentioning", "search all transcripts for",
                    "pull up the set with", "find where I riffed on"
                ]
            ),
            BitBuddyIntent(
                id: "clip_recording",
                section: .recordings, category: .edit,
                description: "Clip or trim a recording.",
                keywords: ["clip", "trim", "cut", "extract", "shorten audio"],
                examplePatterns: [
                    "clip this recording", "trim the dead air at the start",
                    "cut the ending applause", "make a shorter audio clip",
                    "trim this set recording", "cut from minute two to minute five",
                    "extract the good section", "make a clip of this riff"
                ]
            ),
            BitBuddyIntent(
                id: "attach_recording_to_set",
                section: .recordings, category: .organize,
                description: "Attach a recording to a set list.",
                keywords: ["attach recording", "link audio", "connect recording", "associate recording"],
                examplePatterns: [
                    "attach this recording to", "link this audio to tonight's set",
                    "connect this recording to that set list",
                    "match this recording with my open mic set",
                    "save this audio under", "associate this recording with the set",
                    "tie this file to the set list", "link this recording to my lineup"
                ]
            ),
            BitBuddyIntent(
                id: "review_set_from_recording",
                section: .recordings, category: .analysis,
                description: "Analyze a set recording for notes.",
                keywords: ["review recording", "analyze recording", "feedback", "summarize recording", "strongest moments"],
                examplePatterns: [
                    "review this set recording", "analyze how this set went",
                    "pull notes from this performance", "give me feedback from this recording",
                    "tell me what changed in this set", "review the transcript for improv moments",
                    "summarize this recording", "find the strongest moments in this set"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: BITBUDDY (16 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "analyze_joke",
                section: .bitbuddy, category: .analysis,
                description: "Analyze the structure and strengths of a joke.",
                keywords: ["analyze", "break down", "structure", "evaluate", "strengths"],
                examplePatterns: [
                    "analyze this joke", "break down why this bit works",
                    "tell me what this joke is doing", "analyze the structure",
                    "what is strong about this joke", "give me a joke analysis",
                    "break this bit apart", "evaluate this joke"
                ]
            ),
            BitBuddyIntent(
                id: "improve_joke",
                section: .bitbuddy, category: .generation,
                description: "Suggest stronger rewrites for a joke.",
                keywords: ["improve", "punch up", "better versions", "rewrite", "stronger", "sharper", "fix"],
                examplePatterns: [
                    "improve this joke", "punch this up", "give me 3 better versions",
                    "rewrite this bit tighter", "make this joke stronger",
                    "punch up the wording", "give me sharper options", "fix this joke"
                ]
            ),
            BitBuddyIntent(
                id: "generate_premise",
                section: .bitbuddy, category: .generation,
                description: "Generate premises from a topic.",
                keywords: ["premise", "premises", "angles", "brainstorm premise"],
                examplePatterns: [
                    "give me a premise about", "generate joke premises for",
                    "what are some premises on", "brainstorm premises about",
                    "give me angles on", "generate premises from this topic",
                    "what are premises for", "start a premise on"
                ]
            ),
            BitBuddyIntent(
                id: "generate_joke",
                section: .bitbuddy, category: .generation,
                description: "Generate a joke or bit from a topic.",
                keywords: ["write", "generate", "make joke", "one-liner", "create bit"],
                examplePatterns: [
                    "write a joke about", "generate a bit on",
                    "give me a joke about", "make a joke from this premise",
                    "write me a one-liner about", "generate a short joke about",
                    "turn this idea into a joke", "write a bit about"
                ]
            ),
            BitBuddyIntent(
                id: "summarize_style",
                section: .bitbuddy, category: .analysis,
                description: "Summarize the user's writing style.",
                keywords: ["style", "comedy style", "voice", "tone", "patterns", "tendencies"],
                examplePatterns: [
                    "what is my comedy style", "summarize how I write",
                    "describe my joke voice", "what patterns do I use the most",
                    "tell me my style profile", "how would you describe my comedy",
                    "show my writing tendencies", "what is my tone"
                ]
            ),
            BitBuddyIntent(
                id: "suggest_unexplored_topics",
                section: .bitbuddy, category: .analysis,
                description: "Suggest topics the user has not explored much.",
                keywords: ["unexplored", "not covering", "gaps", "fresh topic", "missing", "underused"],
                examplePatterns: [
                    "what topics am I not covering", "suggest a topic I have not mined yet",
                    "what have I barely written about", "show me underused areas",
                    "what should I explore next", "find gaps in my material",
                    "suggest a fresh topic", "tell me what I am missing"
                ]
            ),
            BitBuddyIntent(
                id: "find_similar_jokes",
                section: .bitbuddy, category: .analysis,
                description: "Find saved jokes similar to a given joke.",
                keywords: ["similar", "like this", "same angle", "related", "overlap", "comparable"],
                examplePatterns: [
                    "find jokes similar to this", "do I already have a bit like this",
                    "show jokes with the same angle", "find related material",
                    "what jokes of mine sound like this", "match this against my joke book",
                    "find overlap with my other bits", "show me comparable jokes"
                ]
            ),
            BitBuddyIntent(
                id: "shorten_joke",
                section: .bitbuddy, category: .generation,
                description: "Make a joke tighter or shorter.",
                keywords: ["shorten", "tighter", "trim", "condense", "cut down", "reduce"],
                examplePatterns: [
                    "shorten this joke", "make this bit tighter", "trim the fat",
                    "condense this joke", "cut this down", "make this one-liner length",
                    "tighten the setup", "reduce the wording"
                ]
            ),
            BitBuddyIntent(
                id: "expand_joke",
                section: .bitbuddy, category: .generation,
                description: "Expand a short joke into a fuller bit.",
                keywords: ["expand", "longer", "build out", "stretch", "full bit", "chunk"],
                examplePatterns: [
                    "expand this into a full bit", "make this joke longer",
                    "build this out", "turn this one-liner into a chunk",
                    "add tags and turns to this bit", "help me stretch this premise",
                    "expand the riff", "turn this into stage material"
                ]
            ),
            BitBuddyIntent(
                id: "generate_tags_for_joke",
                section: .bitbuddy, category: .analysis,
                description: "Suggest tags for a joke.",
                keywords: ["auto-tag", "suggest tags", "generate tags", "categorize", "themes", "labels"],
                examplePatterns: [
                    "what tags fit this joke", "tag this for me",
                    "generate tags for this bit", "how should I categorize this joke",
                    "give this joke some tags", "what themes are in this",
                    "suggest labels for this joke", "auto-tag this"
                ]
            ),
            BitBuddyIntent(
                id: "rewrite_in_my_style",
                section: .bitbuddy, category: .generation,
                description: "Rewrite material in the user's existing style.",
                keywords: ["my style", "my voice", "sound like me", "more me", "adapt"],
                examplePatterns: [
                    "rewrite this in my style", "make this sound more like me",
                    "use my voice on this joke", "rework this so it feels like my material",
                    "match my style here", "rewrite this like I would say it",
                    "make this more me", "adapt this to my voice"
                ]
            ),
            BitBuddyIntent(
                id: "crowdwork_help",
                section: .bitbuddy, category: .generation,
                description: "Generate crowdwork lines or approaches.",
                keywords: ["crowdwork", "crowd", "audience", "front row", "riff", "heckler"],
                examplePatterns: [
                    "give me crowdwork questions", "how should I open crowdwork with a couple",
                    "generate tags for a drunk audience member", "give me clean crowdwork lines",
                    "help me riff on a late arrival", "what is a crowdwork angle",
                    "give me a crowdwork opener", "help me handle someone in the front row"
                ]
            ),
            BitBuddyIntent(
                id: "roast_line_generation",
                section: .bitbuddy, category: .generation,
                description: "Generate roast lines.",
                keywords: ["roast lines", "burns", "roast joke", "roast material", "roast"],
                examplePatterns: [
                    "give me roast lines for", "write roasts about",
                    "generate a few burns", "help me roast",
                    "give me sharper roast jokes", "write roast material",
                    "generate fire for this target", "help me with roast lines"
                ]
            ),
            BitBuddyIntent(
                id: "compare_versions",
                section: .bitbuddy, category: .analysis,
                description: "Compare multiple joke versions.",
                keywords: ["compare", "which version", "which draft", "stronger", "pros and cons"],
                examplePatterns: [
                    "which version is stronger", "compare these two punchlines",
                    "tell me which draft is better", "pick the stronger joke version",
                    "compare these rewrites", "which wording lands harder",
                    "evaluate both versions", "show the pros and cons"
                ]
            ),
            BitBuddyIntent(
                id: "extract_premises_from_notes",
                section: .bitbuddy, category: .analysis,
                description: "Extract joke premises from loose notes.",
                keywords: ["extract premises", "pull premises", "find angles", "mine", "usable angles"],
                examplePatterns: [
                    "pull premises out of this note", "find joke angles in this mess",
                    "extract possible premises from this paragraph",
                    "turn these raw thoughts into premises", "what premises are hiding in here",
                    "mine this note for bits", "pull joke ideas from this",
                    "what are the usable angles here"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: NOTEBOOK (4 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "open_notebook",
                section: .notebook, category: .navigation,
                description: "Open the Notebook section.",
                keywords: ["open notebook", "notebook", "notepad", "notes", "writing pad"],
                examplePatterns: [
                    "open notebook", "take me to my notebook",
                    "go to the notepad", "open the quick notebook",
                    "show the notebook page", "switch to notebook",
                    "open my notes", "go to the writing pad"
                ]
            ),
            BitBuddyIntent(
                id: "save_notebook_text",
                section: .notebook, category: .capture,
                description: "Save freeform text to the notebook.",
                keywords: ["save notebook", "add notebook", "write notebook", "store notebook"],
                examplePatterns: [
                    "save this in notebook", "add this to my notebook",
                    "put this thought in the notebook", "drop this into notes",
                    "save this as a notebook entry", "write this in notebook",
                    "add a note with this text", "store this in the notepad"
                ]
            ),
            BitBuddyIntent(
                id: "attach_photo_to_notebook",
                section: .notebook, category: .capture,
                description: "Attach a photo to the notebook.",
                keywords: ["photo notebook", "image notebook", "picture notebook", "screenshot notebook"],
                examplePatterns: [
                    "attach this photo to my notebook", "add an image to this note",
                    "save this picture in notebook", "put this photo in my notes",
                    "attach an image to the notebook", "save this screenshot in notebook",
                    "add this image to my notepad", "keep this photo with my notes"
                ]
            ),
            BitBuddyIntent(
                id: "search_notebook",
                section: .notebook, category: .search,
                description: "Search notebook content.",
                keywords: ["search notebook", "find notebook", "search notes", "find notes"],
                examplePatterns: [
                    "search my notebook for", "find my notes about",
                    "look through notebook for", "search notes for",
                    "find the note about", "search notebook for",
                    "pull up notes mentioning", "find notebook entries with"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: ROAST MODE (7 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "toggle_roast_mode",
                section: .roastMode, category: .settings,
                description: "Turn Roast Mode on or off.",
                keywords: ["roast mode", "enable roast", "disable roast", "toggle roast"],
                examplePatterns: [
                    "turn on roast mode", "enable roast mode",
                    "switch the app into roast mode", "turn roast mode off",
                    "disable roast mode", "put bitbinder in roast mode",
                    "leave roast mode", "toggle roast mode"
                ]
            ),
            BitBuddyIntent(
                id: "create_roast_target",
                section: .roastMode, category: .capture,
                description: "Create a roast target.",
                keywords: ["roast target", "new target", "add target", "roast profile"],
                examplePatterns: [
                    "add a roast target called", "create a new roast target",
                    "make a target for", "add someone to roasts",
                    "start a roast folder for", "create a roast profile",
                    "new target called", "add a person to roast"
                ]
            ),
            BitBuddyIntent(
                id: "add_roast_joke",
                section: .roastMode, category: .capture,
                description: "Save a roast joke under a target.",
                keywords: ["roast joke", "burn", "insult", "roast under"],
                examplePatterns: [
                    "save this roast under", "add this burn to",
                    "put this roast joke on", "add a roast line for",
                    "store this under that roast target", "save this insult to",
                    "add this joke to the roast target", "file this roast under"
                ]
            ),
            BitBuddyIntent(
                id: "search_roasts",
                section: .roastMode, category: .search,
                description: "Search roast material.",
                keywords: ["search roast", "find roast", "show burns", "look up roast"],
                examplePatterns: [
                    "find roasts about", "search my roast jokes for",
                    "show burns for", "look up roast lines about",
                    "search roasts for", "find all my roasts on",
                    "pull up roast material about", "search roast targets and jokes"
                ]
            ),
            BitBuddyIntent(
                id: "create_roast_set",
                section: .roastMode, category: .capture,
                description: "Create a roast set list.",
                keywords: ["roast set", "burn set", "roast lineup", "roast performance"],
                examplePatterns: [
                    "create a roast set", "make a roast set for battle night",
                    "start a roast lineup", "build me a roast set list",
                    "create a set of burns for", "make a roast performance set",
                    "new roast set", "start a burn set"
                ]
            ),
            BitBuddyIntent(
                id: "present_roast_set",
                section: .roastMode, category: .present,
                description: "Open presenter view for a roast set.",
                keywords: ["present roast", "roast presentation", "roast performance", "roast stage"],
                examplePatterns: [
                    "present this roast set", "open the roast presentation view",
                    "show this burn set in performance mode", "present my roasts",
                    "start roast presenter mode", "open the stage version of this roast set",
                    "go into roast performance view", "present the burns"
                ]
            ),
            BitBuddyIntent(
                id: "attach_photo_to_target",
                section: .roastMode, category: .capture,
                description: "Attach a photo to a roast target.",
                keywords: ["photo target", "image target", "target photo", "face photo"],
                examplePatterns: [
                    "add a photo to this roast target", "attach this image to",
                    "set a target photo", "save this picture on the roast profile",
                    "add a face photo for", "upload a photo to the target",
                    "give this roast target an image", "attach this picture here"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: IMPORT (7 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "import_file",
                section: .importFlow, category: .capture,
                description: "Import jokes from a file.",
                keywords: ["import", "pdf", "bring in", "file", "document", "gaggrabber"],
                examplePatterns: [
                    "import a pdf of my jokes", "bring in this file",
                    "import jokes from a document", "use gaggrabber on this file",
                    "pull jokes out of this pdf", "import material from this text file",
                    "add jokes from a document", "scan this file into bitbinder"
                ]
            ),
            BitBuddyIntent(
                id: "import_image",
                section: .importFlow, category: .capture,
                description: "Import jokes from an image or scan.",
                keywords: ["import image", "scan", "ocr", "screenshot", "handwritten", "photo import"],
                examplePatterns: [
                    "import jokes from this image", "scan this page of notes",
                    "use ocr on this photo", "pull jokes from this screenshot",
                    "import from a picture", "read this handwritten page",
                    "extract jokes from this image", "scan this note into the app"
                ]
            ),
            BitBuddyIntent(
                id: "review_import_queue",
                section: .importFlow, category: .review,
                description: "Review imported jokes that need approval.",
                keywords: ["review import", "import queue", "approval", "pending imports", "review queue"],
                examplePatterns: [
                    "show me the import review queue", "review my imported jokes",
                    "open the jokes that need approval", "show imports waiting for review",
                    "take me to import review", "let me approve imported bits",
                    "open the review queue", "show rejected and pending imports"
                ]
            ),
            BitBuddyIntent(
                id: "approve_imported_joke",
                section: .importFlow, category: .review,
                description: "Approve an imported joke.",
                keywords: ["approve", "keep", "accept", "save imported"],
                examplePatterns: [
                    "approve this imported joke", "keep this one",
                    "save this imported bit", "approve this result",
                    "accept this imported joke", "keep this joke from the import",
                    "approve the selected import", "save this extracted joke"
                ]
            ),
            BitBuddyIntent(
                id: "reject_imported_joke",
                section: .importFlow, category: .review,
                description: "Reject an imported joke.",
                keywords: ["reject", "discard", "skip", "throw away import"],
                examplePatterns: [
                    "reject this imported joke", "throw this import away",
                    "do not save this one", "reject this result",
                    "delete this extracted joke", "skip this imported bit",
                    "discard this import", "trash this extracted joke"
                ]
            ),
            BitBuddyIntent(
                id: "edit_imported_joke",
                section: .importFlow, category: .review,
                description: "Edit an imported joke before saving.",
                keywords: ["edit import", "fix import", "clean import", "repair import", "adjust import"],
                examplePatterns: [
                    "edit this imported joke first", "fix the split on this import",
                    "clean up this extracted joke", "edit before approving",
                    "repair this imported text", "adjust the wording on this import",
                    "merge the lines on this one", "fix this import before saving"
                ]
            ),
            BitBuddyIntent(
                id: "check_import_limit",
                section: .importFlow, category: .status,
                description: "Check GagGrabber extraction limit status.",
                keywords: ["grabs left", "import limit", "quota", "extraction count", "remaining grabs", "daily limit"],
                examplePatterns: [
                    "how many grabs do I have left", "check my gaggrabber limit",
                    "how many imports are left today", "show import quota",
                    "what is my extraction count", "tell me my remaining grabs",
                    "check the daily import limit", "how much import usage is left"
                ]
            ),
            BitBuddyIntent(
                id: "show_import_history",
                section: .importFlow, category: .status,
                description: "Show previous import activity.",
                keywords: ["import history", "recent imports", "import log", "imported files"],
                examplePatterns: [
                    "show my import history", "what files did I import recently",
                    "list recent imports", "show previous gaggrabber jobs",
                    "pull up my import log", "show imported files from this week",
                    "what have I already imported", "open import history"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: SYNC (3 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "check_sync_status",
                section: .sync, category: .status,
                description: "Check iCloud sync status.",
                keywords: ["sync status", "icloud", "cloudkit", "synced", "last synced"],
                examplePatterns: [
                    "check icloud sync", "show my sync status",
                    "did my jokes sync", "is bitbinder synced",
                    "show cloudkit status", "tell me when I last synced",
                    "check whether everything is uploaded", "show icloud sync details"
                ]
            ),
            BitBuddyIntent(
                id: "sync_now",
                section: .sync, category: .action,
                description: "Force a manual sync.",
                keywords: ["sync now", "manual sync", "push", "force sync", "upload changes"],
                examplePatterns: [
                    "sync now", "run icloud sync now",
                    "push my data to icloud", "start a manual sync",
                    "sync everything right now", "force a cloud sync",
                    "upload changes now", "run sync"
                ]
            ),
            BitBuddyIntent(
                id: "toggle_icloud_sync",
                section: .sync, category: .settings,
                description: "Enable or disable iCloud sync.",
                keywords: ["toggle sync", "enable sync", "disable sync", "turn on sync", "turn off sync"],
                examplePatterns: [
                    "turn on icloud sync", "enable cloud sync",
                    "turn off icloud sync", "disable syncing",
                    "toggle icloud sync", "use cloudkit for this app",
                    "stop syncing for now", "enable sync across devices"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: SETTINGS (3 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "export_all_jokes",
                section: .settings, category: .export,
                description: "Export all jokes.",
                keywords: ["export all", "backup jokes", "download jokes", "full export"],
                examplePatterns: [
                    "export all my jokes", "back up my joke book",
                    "make a full joke export", "export every joke",
                    "download all of my material", "create a jokes backup",
                    "export the whole jokes section", "save all jokes out of the app"
                ]
            ),
            BitBuddyIntent(
                id: "export_recordings",
                section: .settings, category: .export,
                description: "Export all recordings.",
                keywords: ["export recordings", "backup audio", "download recordings"],
                examplePatterns: [
                    "export all recordings", "back up my audio files",
                    "export every set recording", "download my recordings",
                    "save all my audio", "export the recordings section",
                    "create a backup of my set audio", "pull all recordings out"
                ]
            ),
            BitBuddyIntent(
                id: "clear_cache",
                section: .settings, category: .manage,
                description: "Clear cached app data.",
                keywords: ["clear cache", "wipe cache", "clean cache", "purge", "temporary files"],
                examplePatterns: [
                    "clear the cache", "wipe cached data",
                    "clean app cache", "delete temporary files",
                    "free up cache storage", "purge the cache",
                    "clear bitbinder cache", "remove cached files"
                ]
            ),

            // ═══════════════════════════════════════════
            // SECTION: HELP (2 intents)
            // ═══════════════════════════════════════════

            BitBuddyIntent(
                id: "open_help_faq",
                section: .help, category: .navigation,
                description: "Open Help and FAQ.",
                keywords: ["help", "faq", "support", "how to"],
                examplePatterns: [
                    "open help", "show faq", "take me to help and faq",
                    "I need help with the app", "open the help section",
                    "show support info", "go to faq", "open app help"
                ]
            ),
            BitBuddyIntent(
                id: "explain_feature",
                section: .help, category: .help,
                description: "Explain a specific feature.",
                keywords: ["how does", "explain", "what does", "how do", "what is", "tell me how"],
                examplePatterns: [
                    "how does gaggrabber work", "explain roast mode",
                    "what does the hits do", "how do set lists work",
                    "explain bitbuddy commands", "what is brainstorm for",
                    "how does import review work", "tell me how icloud sync works"
                ]
            ),
        ]
    }
    // swiftlint:enable function_body_length
}
