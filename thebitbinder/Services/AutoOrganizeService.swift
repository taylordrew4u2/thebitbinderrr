//
//  AutoOrganizeService.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/7/25.
//

import Foundation
import SwiftData

struct StyleAnalysis {
    let tags: [String]
    let tone: String?
    let craftSignals: [String]
    let structureScore: Double
    let hook: String?
}

struct TopicMatch {
    let category: String
    let confidence: Double
    let evidence: [String]
}

// MARK: - Joke Structure Analysis
struct JokeStructure {
    let hasSetup: Bool
    let hasPunchline: Bool
    let format: JokeFormat
    let wordplayScore: Double
    let setupLineCount: Int
    let punchlineLineCount: Int
    let questionAnswerPattern: Bool
    let storyTwistPattern: Bool
    let oneLiners: Int
    let dialogueCount: Int
    
    var structureConfidence: Double {
        var score = 0.0
        if hasSetup { score += 0.2 }
        if hasPunchline { score += 0.2 }
        score += min(wordplayScore * 0.2, 0.2)
        if questionAnswerPattern { score += 0.15 }
        if storyTwistPattern { score += 0.15 }
        return min(score, 1.0)
    }
}

enum JokeFormat {
    case questionAnswer
    case storyTwist
    case oneLiner
    case dialogue
    case sequential
    case unknown
}

// MARK: - Pattern Match Result
// Wordplay detection helpers
let homophoneSets: [[String]] = [
    ["to", "too", "two"],
    ["be", "bee"],
    ["see", "sea"],
    ["here", "hear"],
    ["write", "right"],
    ["mail", "male"],
    ["knight", "night"]
]

let doubleMeaningWords: [(String, String)] = [
    ("bark", "tree coating or dog sound"),
    ("bank", "financial or river side"),
    ("can", "is able or container"),
    ("date", "calendar or romantic outing"),
    ("fair", "just or carnival")
]


class AutoOrganizeService {

    // MARK: - AI-Powered Categorization

    /// Uses a configured AI provider to categorize a joke into comedy categories.
    /// Falls back to local heuristics if no AI provider is available or the call fails.
    /// - Parameters:
    ///   - content: The joke text to categorize.
    ///   - existingFolders: Optional list of existing folder names to prefer.
    /// - Returns: An array of `CategoryMatch` with AI-powered suggestions.
    static func aiCategorize(content: String, existingFolders: [String] = []) async -> [CategoryMatch] {
        // Try AI providers in the user's preferred order
        let manager = AIJokeExtractionManager.shared
        let providerOrder = manager.providerOrder
        let disabledProviders = manager.disabledProviders

        for providerType in providerOrder {
            guard !disabledProviders.contains(providerType) else { continue }
            guard AIKeyLoader.loadKey(for: providerType) != nil else { continue }

            do {
                let matches = try await callAIForCategorization(content: content, provider: providerType, existingFolders: existingFolders)
                if !matches.isEmpty {
                    #if DEBUG
                    print(" [AutoOrganize-AI] Got \(matches.count) categories from \(providerType.displayName)")
                    #endif
                    return matches
                }
            } catch {
                #if DEBUG
                print(" [AutoOrganize-AI] \(providerType.displayName) failed: \(error.localizedDescription)")
                #endif
                continue
            }
        }

        // Fallback to local heuristics if no AI provider worked
        #if DEBUG
        print(" [AutoOrganize-AI] No AI provider available, falling back to local heuristics")
        #endif
        return categorize(content: content)
    }

    /// Sends a categorization request to an AI provider and parses the response.
    private static func callAIForCategorization(content: String, provider: AIProviderType, existingFolders: [String]) async throws -> [CategoryMatch] {
        guard let apiKey = AIKeyLoader.loadKey(for: provider) else {
            throw AIProviderError.keyNotConfigured(provider)
        }

        let folderContext: String
        if !existingFolders.isEmpty {
            folderContext = "\n\nExisting folders the user has: \(existingFolders.joined(separator: ", ")). Prefer these when they fit, but suggest new ones if needed."
        } else {
            folderContext = ""
        }

        let prompt = """
        You are a comedy categorization assistant. Analyze this joke/bit and suggest 1-3 comedy categories that best describe it.

        For each category, provide:
        - category: A short category name (e.g. "Observational", "Self-Deprecating", "Dark Humor", "Puns", "Anecdotal", "One-Liners", "Roasts", "Satire", "Sarcasm", "Dad Jokes", "Wordplay", "Storytelling", "Crowd Work", "Physical Comedy", "Topical", "Absurdist", or any fitting comedy category)
        - confidence: A number from 0.0 to 1.0
        - reasoning: A brief explanation of why this category fits\(folderContext)

        Return ONLY a valid JSON array, no markdown fences, no extra text:
        [{"category":"<name>","confidence":<0.0-1.0>,"reasoning":"<why>","keywords":["keyword1"]}]

        --- JOKE ---
        \(content)
        """

        let endpoint: String
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(apiKey)"
        ]

        switch provider {
        case .openAI:
            endpoint = "https://api.openai.com/v1/chat/completions"
        case .arceeAI, .openRouter:
            endpoint = "https://openrouter.ai/api/v1/chat/completions"
            headers["HTTP-Referer"] = "https://openrouter.ai"
            headers["X-Title"] = "thebitbinder"
        }

        let model = provider.defaultModel

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a JSON API. Output ONLY valid JSON arrays. No markdown, no prose."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 1024
        ]

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AIProviderError.apiError(provider, "HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let rawContent = message["content"] as? String else {
            throw AIProviderError.apiError(provider, "Invalid response format")
        }

        return parseCategorizationResponse(rawContent)
    }

    /// Parses the AI response JSON into CategoryMatch objects.
    private static func parseCategorizationResponse(_ raw: String) -> [CategoryMatch] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown fences
        if cleaned.hasPrefix("```") {
            if let startRange = cleaned.range(of: "\n") {
                cleaned = String(cleaned[startRange.upperBound...])
            }
            if let endRange = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<endRange.lowerBound])
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return parsed.compactMap { entry -> CategoryMatch? in
            guard let category = entry["category"] as? String else { return nil }
            let confidence = (entry["confidence"] as? Double) ?? 0.7
            let reasoning = (entry["reasoning"] as? String) ?? "AI-suggested category"
            let keywords = (entry["keywords"] as? [String]) ?? []

            return CategoryMatch(
                category: category,
                confidence: confidence,
                reasoning: reasoning,
                matchedKeywords: keywords,
                styleTags: [],
                emotionalTone: nil,
                craftSignals: [],
                structureScore: 0
            )
        }
    }

    /// Returns true if at least one AI provider is configured and enabled.
    static var isAIAvailable: Bool {
        let manager = AIJokeExtractionManager.shared
        let disabled = manager.disabledProviders
        for provider in manager.providerOrder {
            if !disabled.contains(provider), AIKeyLoader.loadKey(for: provider) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Local Categorization

    /// Categorizes a single joke content into categories with detailed metadata.
    /// - Parameter content: The joke content to categorize.
    /// - Returns: An array of `CategoryMatch` representing the best matching categories.
    static func categorize(content: String) -> [CategoryMatch] {
        let normalized = normalize(content)
        let topicMatches = scoreCategories(in: normalized)
        let style = analyzeStyle(in: normalized)
        let structure = analyzeJokeStructure(content)
        let matches: [CategoryMatch] = topicMatches.map { match in
            CategoryMatch(
                category: match.category,
                confidence: match.confidence,
                reasoning: reasoning(for: match, style: style, structure: structure),
                matchedKeywords: match.evidence,
                styleTags: style.tags,
                emotionalTone: style.tone,
                craftSignals: style.craftSignals,
                structureScore: structure.structureConfidence
            )
        }
        .sorted { $0.confidence > $1.confidence }
        return matches
    }

    // MARK: - Configuration
    private static let confidenceThresholdForAutoOrganize: Double = 0.40
    private static let confidenceThresholdForSuggestion: Double = 0.20
    private static let multiCategoryThreshold: Double = 0.35
    
    // MARK: - Comedy Category Lexicon
    private static let categories: [String: CategoryKeywords] = [
        "Puns": CategoryKeywords(keywords: [("pun", 1.0), ("wordplay", 1.0), ("play on words", 1.0), ("double meaning", 0.9), ("homophone", 0.9), ("fruit flies", 0.8), ("arrow", 0.6)]),
        "Roasts": CategoryKeywords(keywords: [("roast", 1.0), ("insult", 0.9), ("you're so", 0.9), ("ugly", 0.9), ("trash", 0.8), ("burn", 0.7)]),
        "One-Liners": CategoryKeywords(keywords: [("one liner", 1.0), ("quick", 0.7), ("short", 0.7), ("punchline", 0.8), ("she looked", 0.7)]),
        "Knock-Knock": CategoryKeywords(keywords: [("knock knock", 1.0), ("who's there", 1.0), ("boo who", 0.9), ("interrupting", 0.8)]),
        "Dad Jokes": CategoryKeywords(keywords: [("dad joke", 1.0), ("scarecrow", 0.9), ("outstanding in his field", 1.0), ("corny", 0.8), ("groan", 0.6)]),
        "Sarcasm": CategoryKeywords(keywords: [("sarcasm", 1.0), ("sarcastic", 1.0), ("oh great", 1.0), ("yeah right", 0.9), ("sure", 0.7)]),
        "Irony": CategoryKeywords(keywords: [("irony", 1.0), ("ironic", 1.0), ("unexpected", 0.8), ("fire station", 0.9), ("burned down", 0.9)]),
        "Satire": CategoryKeywords(keywords: [("satire", 1.0), ("satirical", 1.0), ("society", 0.8), ("politics", 0.8), ("the daily show", 1.0)]),
        "Dark Humor": CategoryKeywords(keywords: [("dark humor", 1.0), ("death", 0.9), ("tragedy", 0.9), ("suicide", 1.0), ("bomber", 0.8), ("blast", 0.7)]),
        "Observational": CategoryKeywords(keywords: [("observational", 1.0), ("why do", 0.9), ("have you ever", 0.9), ("driveway", 0.8), ("parkway", 0.8)]),
        "Anecdotal": CategoryKeywords(keywords: [("one time", 1.0), ("story", 0.8), ("this happened", 0.9), ("friend", 0.7), ("drunk", 0.6)]),
        "Self-Deprecating": CategoryKeywords(keywords: [("self deprecating", 1.0), ("i'm so", 0.9), ("i'm not", 0.9), ("i suck", 0.8), ("i'm terrible", 0.8)]),
        "Anti-Jokes": CategoryKeywords(keywords: [("anti joke", 1.0), ("not really a joke", 0.9), ("why did the chicken", 0.9), ("other side", 0.8)]),
        "Riddles": CategoryKeywords(keywords: [("riddle", 1.0), ("what has", 1.0), ("clever answer", 0.9), ("legs", 0.7), ("morning", 0.6), ("evening", 0.6)]),
        "Other": CategoryKeywords(keywords: [], weight: 0.2)
    ]
    
    /// Public accessor for available category names used for organizing jokes
    static func getCategories() -> [String] {
        // Expose keys of the internal categories lexicon, sorted alphabetically with "Other" last
        let names = Array(categories.keys)
        let sorted = names.sorted { a, b in
            if a == "Other" { return false }
            if b == "Other" { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return sorted
    }
    
    // MARK: - Style Lexicons
    private static let styleCueLexicon: [String: [String]] = [
        "Self-Deprecating": ["i'm so", "i'm not", "i suck", "i'm terrible"],
        "Observational": ["have you ever", "why do", "isn't it weird"],
        "Anecdotal": ["one time", "story", "so there i was"],
        "Sarcasm": ["yeah right", "sure", "great", "wonderful", "of course"],
        "Dark": ["death", "suicide", "funeral", "grave"],
        "Satire": ["society", "politics", "system", "corporate"],
        "Roast": ["you're so", "look at you", "sit down"],
        "Dad": ["dad", "kids", "son", "daughter"],
        "Wordplay": ["pun", "wordplay", "double meaning"],
        "Anti-Joke": ["not even a joke", "literal", "just"],
        "Knock-Knock": ["knock knock", "who's there"],
        "Riddle": ["what has", "who am i", "clever answer"],
        "Irony": ["ironically", "turns out", "of course the"],
        "One-Liner": ["short", "quick", "line"],
        "Story": ["long story", "cut to", "flash forward"],
        "Blue": ["explicit", "naughty", "bedroom"],
        "Topical": ["today", "headline", "trending"],
        "Crowd": ["sir", "ma'am", "front row"]
    ]
    
    private static let toneKeywords: [String: [String]] = [
        "Playful": ["lol", "haha", "silly", "goofy"],
        "Cynical": ["of course", "naturally", "figures"],
        "Angry": ["hate", "furious", "annoyed"],
        "Confessional": ["honestly", "truth", "real talk"],
        "Dark": ["death", "suicide", "grave"],
        "Hopeful": ["maybe", "believe", "hope"],
        "Cringe": ["awkward", "embarrassing"]
    ]
    
    private static let craftSignalsLexicon: [String: [String]] = [
        "Rule of Three": ["first", "second", "third", "one", "two", "three"],
        "Callback": ["again", "like before", "remember"],
        "Misdirection": ["but", "instead", "actually", "turns out"],
        "Act-Out": ["(acts", "[act", "stage"],
        "Crowd Work": ["sir", "ma'am", "front row", "table"],
        "Question/Punch": ["?", "answer is", "because"],
        "Absurd Heighten": ["then suddenly", "escalated", "spiraled"]
    ]
    
    
    /// Analyzes joke structure heuristics for a given text
    private static func analyzeJokeStructure(_ text: String) -> JokeStructure {
        let lower = text.lowercased()
        let hasQ = lower.contains("?") || lower.contains("why ") || lower.contains("what ") || lower.contains("how ")
        let hasAnswerIndicators = lower.contains("because") || lower.contains("so ") || lower.contains("that's why")
        let lines = text.split(separator: "\n").map { String($0) }
        let setupLines = lines.prefix { !$0.contains("?") }.count
        let punchLines = max(1, lines.count - setupLines)

        // Wordplay heuristic using homophones/double meanings already defined
        var wordplay = 0.0
        for set in homophoneSets {
            let present = set.filter { lower.contains($0) }
            if present.count >= 2 { wordplay += 0.5; break }
        }
        for (word, _) in doubleMeaningWords { if lower.contains(word) { wordplay += 0.1 } }
        wordplay = min(wordplay, 1.0)

        // Determine format
        let format: JokeFormat
        if lower.contains("knock knock") { format = .sequential }
        else if hasQ && hasAnswerIndicators { format = .questionAnswer }
        else if lines.count <= 2 && text.count < 140 { format = .oneLiner }
        else if lower.contains("\n") && (lower.contains("then ") || lower.contains("turns out") || lower.contains("but ")) { format = .storyTwist }
        else { format = .unknown }

        return JokeStructure(
            hasSetup: hasQ || setupLines > 0,
            hasPunchline: hasAnswerIndicators || punchLines > 0,
            format: format,
            wordplayScore: wordplay,
            setupLineCount: setupLines,
            punchlineLineCount: punchLines,
            questionAnswerPattern: format == .questionAnswer,
            storyTwistPattern: format == .storyTwist,
            oneLiners: format == .oneLiner ? 1 : 0,
            dialogueCount: lower.components(separatedBy: ": ").count - 1
        )
    }
    
    private static func scoreCategories(in text: String) -> [TopicMatch] {
        var results: [TopicMatch] = []
        for (category, keywords) in categories {
            let hits = keywords.keywords.filter { text.containsWord($0.0) }
            guard !hits.isEmpty else { continue }
            let weightSum = keywords.keywords.reduce(0.0) { $0 + $1.1 }
            let score = hits.reduce(0.0) { $0 + $1.1 }
            let lengthBoost = min(Double(text.count) / 800.0, 0.15)
            let confidence = min(1.0, (score / max(weightSum, 1.0)) + lengthBoost)
            results.append(TopicMatch(category: category, confidence: confidence, evidence: hits.map { $0.0 }))
        }
        return results.sorted { $0.confidence > $1.confidence }
    }
    
    private static func analyzeStyle(in text: String) -> StyleAnalysis {
        var styleScores: [(String, Int)] = []
        for (tag, cues) in styleCueLexicon {
            let hits = cues.filter { text.contains($0) }
            guard !hits.isEmpty else { continue }
            styleScores.append((tag, hits.count))
        }
        let tags = styleScores.sorted { $0.1 > $1.1 }.map { $0.0 }.prefix(4)
        
        var toneScores: [(String, Int)] = []
        for (tone, cues) in toneKeywords {
            let hits = cues.filter { text.contains($0) }
            if !hits.isEmpty { toneScores.append((tone, hits.count)) }
        }
        let tone = toneScores.sorted { $0.1 > $1.1 }.first?.0
        
        var craftHits: [String] = []
        for (signal, cues) in craftSignalsLexicon {
            if cues.contains(where: { text.contains($0) }) {
                craftHits.append(signal)
            }
        }
        
        var structureScore = 0.0
        if text.contains("setup") { structureScore += 0.15 }
        if text.contains("punchline") { structureScore += 0.15 }
        if text.contains("tag") { structureScore += 0.1 }
        let questionMarks = text.components(separatedBy: "?").count - 1
        structureScore += min(0.2, Double(max(0, questionMarks)) * 0.05)
        structureScore = min(1.0, structureScore)
        
        return StyleAnalysis(tags: Array(tags), tone: tone, craftSignals: craftHits, structureScore: structureScore, hook: tags.first ?? tone)
    }
    
    private static func reasoning(for match: TopicMatch, style: StyleAnalysis, structure: JokeStructure) -> String {
        let confidenceText: String
        switch match.confidence {
        case 0.75...: confidenceText = "very confident"
        case 0.5..<0.75: confidenceText = "confident"
        case 0.35..<0.5: confidenceText = "moderately confident"
        default: confidenceText = "suggested"
        }
        
        var details: [String] = []
        
        if let hook = style.hook {
            details.append("\(hook) vibe")
        }
        
        if structure.structureConfidence > 0.6 {
            details.append("strong structure")
        }
        
        if structure.wordplayScore > 0.5 {
            details.append("wordplay detected")
        }
        
        if !details.isEmpty {
            return "Matches \(match.evidence.count) cues, \(details.joined(separator: ", ")) — \(confidenceText)."
        }
        
        return "Matches \(match.evidence.count) cues — \(confidenceText)."
    }
    
    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

struct CategoryKeywords {
    let keywords: [(String, Double)]
    let weight: Double
    init(keywords: [(String, Double)], weight: Double = 1.0) {
        self.keywords = keywords
        self.weight = weight
    }
}

extension String {
    func containsWord(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(startIndex..., in: self)
            return regex.firstMatch(in: self, options: [], range: range) != nil
        } catch {
            return contains(word)
        }
    }
}
