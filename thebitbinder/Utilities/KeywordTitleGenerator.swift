//
//  KeywordTitleGenerator.swift
//  thebitbinder
//
//  Generates a short keyword-based title from joke content
//  when the user hasn't provided an explicit title.
//

import Foundation

enum KeywordTitleGenerator {

    // MARK: - Public API

    /// Returns a short keyword snippet (2-4 words) from the content,
    /// suitable for display as a fallback title.
    /// Example: "crowd work parking lot" → "Crowd Work Parking"
    static func title(from content: String) -> String {
        let words = significantWords(from: content)
        guard !words.isEmpty else { return "" }
        let picked = Array(words.prefix(4))
        return picked.joined(separator: " ")
    }

    /// Same as `title(from:)` but appends an ellipsis when the content
    /// was truncated, making it clear the title is a preview.
    static func displayTitle(from content: String) -> String {
        let words = significantWords(from: content)
        guard !words.isEmpty else { return "" }
        let picked = Array(words.prefix(4))
        let base = picked.joined(separator: " ")
        let totalSignificant = words.count
        return totalSignificant > 4 ? "\(base)…" : base
    }

    // MARK: - Internal

    /// Common English stop-words that don't carry meaning.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "is", "are", "was",
        "were", "be", "been", "being", "have", "has", "had", "do",
        "does", "did", "will", "would", "shall", "should", "may",
        "might", "must", "can", "could", "i", "me", "my", "mine",
        "we", "us", "our", "you", "your", "he", "him", "his", "she",
        "her", "it", "its", "they", "them", "their", "this", "that",
        "these", "those", "of", "in", "to", "for", "with", "on",
        "at", "from", "by", "about", "as", "into", "through",
        "during", "before", "after", "so", "if", "then", "than",
        "too", "very", "just", "not", "no", "all", "any", "both",
        "each", "few", "more", "most", "other", "some", "such",
        "up", "out", "off", "over", "under", "again", "there",
        "here", "when", "where", "why", "how", "what", "which",
        "who", "whom", "like", "got", "get", "go", "went", "going",
        "know", "said", "say", "im", "dont", "ive", "youre", "thats",
        "really", "yeah", "oh", "well", "um", "uh", "ok", "okay"
    ]

    /// Extract significant (non-stop) words from text, preserving order.
    private static func significantWords(from text: String) -> [String] {
        // Take only the first ~120 chars to keep it fast and relevant
        let prefix = String(text.prefix(120))
        let cleaned = prefix
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .punctuationCharacters).joined()
        let raw = cleaned
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let significant = raw.filter { !stopWords.contains($0.lowercased()) }

        // If everything was a stop word, fall back to the first raw words
        if significant.isEmpty {
            return Array(raw.prefix(3)).map { $0.capitalized }
        }

        return significant.map { $0.capitalized }
    }
}
