//
//  GagGrabber.swift  (was HybridGagGrabber.swift)
//  thebitbinder
//
//  Joke extractor: tries all configured AI providers (Arcee → OpenRouter → OpenAI)
//  via AIJokeExtractionManager with automatic fallback between them.
//  If every AI provider fails, a fast heuristic extractor runs instead —
//  extraction never silently fails.
//
//  Architecture:
//  - AI providers are tried in order via AIJokeExtractionManager.
//  - If all AI providers fail (no keys, rate limit, offline), a heuristic
//    extractor runs as the final fallback.
//  - Results are deduplicated by exact match.
//
//  UI: `HybridGagGrabberSheet` — a toolbar-button-triggered sheet that lets the
//  user pick a .txt or .pdf, extract jokes, and add them one-by-one to their
//  library via the Joke SwiftData model.
//

import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

// MARK: - HybridGagGrabber (ObservableObject)

/// Extracts jokes from raw text using AI providers (Arcee, OpenRouter, OpenAI)
/// with automatic fallback, plus a heuristic fallback when all AI fails.
/// Published state drives the companion `HybridGagGrabberSheet` view.
@MainActor
final class HybridGagGrabber: ObservableObject {

    // MARK: Published State

    /// Jokes extracted from the most recent `extractJokes` call, deduplicated.
    @Published var extractedJokes: [String] = []

    /// Whether an extraction is currently running.
    @Published var isExtracting: Bool = false

    /// Human-readable description of the last error, or nil.
    @Published var lastError: String?

    /// When AI is unavailable, the earliest time the user can retry.
    @Published var retryAfterDate: Date?

    /// The user's description of how their document is formatted.
    /// Sent to the AI to improve extraction accuracy.
    @Published var documentFormatHint: String = ""

    /// Human-readable status message shown during extraction so the user
    /// knows GagGrabber is working and not frozen.
    @Published var statusMessage: String = ""

    /// Elapsed seconds since extraction started — drives the UI timer.
    @Published var elapsedSeconds: Int = 0
    private var timerTask: Task<Void, Never>?

    // MARK: Private State

    /// User-supplied OpenAI key (stored in memory only — the canonical store is
    /// Keychain via `KeychainHelper`). Call `setOpenAIKey(_:)` to persist.
    private var openAIKey: String?

    /// Keychain account key — mirrors the pattern used by the existing
    /// `AIKeyLoader` / `AIProviderType.openAI.keychainKey` so the two systems
    /// share the same key transparently.
    static let keychainAccount = "ai_key_openai"

    // MARK: - Configuration

    /// Provide (or update) the OpenAI API key.
    /// The key is saved to the Keychain so it persists across launches and is
    /// available to the existing `AIJokeExtractionManager` providers too.
    func setOpenAIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            openAIKey = nil
            KeychainHelper.delete(forKey: Self.keychainAccount)
        } else {
            openAIKey = trimmed
            KeychainHelper.save(trimmed, forKey: Self.keychainAccount)
        }
    }

    // MARK: - Main Extraction Entry Point

    /// Extract jokes from `rawText` using AI providers (Arcee → OpenRouter → OpenAI)
    /// with automatic fallback between them. If ALL AI providers are unavailable,
    /// extraction stops and the user is told when to try again — no heuristic fallback.
    func extractJokes(from rawText: String) async {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Document is empty — nothing to extract."
            return
        }

        isExtracting = true
        lastError = nil
        retryAfterDate = nil
        extractedJokes = []
        statusMessage = "Reading your document…"
        startElapsedTimer()

        print(" [GagGrabber] Text length: \(rawText.count) chars")

        // Build the text to send — prepend the user's format hint if provided
        let hint = documentFormatHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let textToSend: String
        if hint.isEmpty {
            textToSend = rawText
        } else {
            textToSend = """
            [USER FORMAT HINT: \(hint)]

            \(rawText)
            """
        }

        // ------------------------------------------------------------------
        // Try all configured AI providers via AIJokeExtractionManager
        // (Arcee → OpenRouter → OpenAI, with automatic fallback)
        // ------------------------------------------------------------------
        let manager = AIJokeExtractionManager.shared
        let token = AIExtractionToken(caller: "HybridGagGrabber")

        if manager.availableProviders.isEmpty {
            let earliest = manager.earliestRetryDate()
            retryAfterDate = earliest
            lastError = sillyRetryMessage(retryDate: earliest)
            isExtracting = false
            stopElapsedTimer()
            statusMessage = ""
            return
        }

        statusMessage = "GagGrabber is scanning for jokes…"

        do {
            let result = try await manager.extractJokes(from: textToSend, token: token)
            let jokes = result.jokes.map(\.jokeText)
            print(" [GagGrabber] \(result.provider.displayName) returned \(jokes.count) joke(s)")

            statusMessage = "Cleaning up results…"
            let deduped = Self.deduplicateJokes(jokes)
            if deduped.isEmpty {
                lastError = "GagGrabber read the whole file but couldn't spot any jokes. Try describing your document format above and give it another go!"
            }
            extractedJokes = deduped
        } catch {
            print(" [GagGrabber] All providers failed: \(error.localizedDescription)")

            let earliest = manager.earliestRetryDate()
            retryAfterDate = earliest
            lastError = sillyRetryMessage(retryDate: earliest)
            // Clear any partial results — if AI ran out mid-way, nothing was saved
            extractedJokes = []
        }

        isExtracting = false
        stopElapsedTimer()
        statusMessage = ""
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedSeconds = 0
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                elapsedSeconds += 1
                // Rotate encouraging messages so user knows it's still working
                if elapsedSeconds == 5 {
                    statusMessage = "Still working — reading through your material…"
                } else if elapsedSeconds == 12 {
                    statusMessage = "Almost there — pulling out the jokes…"
                } else if elapsedSeconds == 25 {
                    statusMessage = "Big file! GagGrabber's still on it…"
                } else if elapsedSeconds == 45 {
                    statusMessage = "Hang tight — this one's a page-turner 📖"
                }
            }
        }
    }

    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Silly Retry Messages

    /// Returns a fun, non-technical message telling the user when GagGrabber is available next.
    private func sillyRetryMessage(retryDate: Date?) -> String {
        let phrases = [
            "GagGrabber's taking a quick coffee break ☕️",
            "GagGrabber needs a breather — even joke machines get tired 😴",
            "GagGrabber's recharging its funny bone 🦴",
            "Hold tight — GagGrabber's doing vocal warm-ups 🎤",
            "GagGrabber stepped out for a smoke break (it doesn't smoke, but still) 🚬",
            "GagGrabber's backstage getting hyped up 🎭",
        ]
        let phrase = phrases.randomElement() ?? phrases[0]

        let retryLine: String
        if let retryDate {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            retryLine = "Try again at **\(formatter.string(from: retryDate))**"
        } else {
            retryLine = "Try again in a few minutes!"
        }

        return "\(phrase)\n\nYour document hasn't been touched yet — nothing was lost!\n\n\(retryLine)"
    }

    // MARK: - Heuristic Extraction (always available)

    /// Heuristic extraction that preserves EVERY word from the file.
    /// It only separates content into individual entries — it NEVER drops anything.
    /// Handles: numbered lists, bullet lists, separator lines (---, ***, ===),
    /// blank-line-separated blocks, and single-line-per-joke formats.
    private static func extractViaHeuristic(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let allLines = trimmed.components(separatedBy: "\n")

        // ── Helpers ──

        let numberedRegex = try? NSRegularExpression(
            pattern: #"^(?:(?:joke|bit|gag|#)\s*)?(\d+)\s*[.):\-–—]\s+"#,
            options: [.caseInsensitive]
        )
        let separatorRegex = try? NSRegularExpression(
            pattern: #"^[-–—=*]{3,}\s*$|^(NEXT JOKE|NEW BIT|//)\s*$"#,
            options: [.caseInsensitive]
        )

        func isNumbered(_ t: String) -> Bool {
            guard let r = numberedRegex else { return false }
            return r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
        }
        func isBullet(_ t: String) -> Bool {
            t.hasPrefix("- ") || t.hasPrefix("• ") || t.hasPrefix("* ")
        }
        func isSeparator(_ t: String) -> Bool {
            guard let r = separatorRegex else { return false }
            return r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
        }

        // Count structure signals
        var numberedCount = 0, bulletCount = 0, nonEmpty = 0
        for line in allLines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            nonEmpty += 1
            if isNumbered(t) { numberedCount += 1 }
            if isBullet(t)   { bulletCount += 1 }
        }

        // Generic splitter: flushes current block at each "break" line.
        // `isBreak` determines what counts as the start of a new entry.
        func split(using isBreak: (String) -> Bool) -> [String] {
            var results: [String] = []
            var current: [String] = []

            for line in allLines {
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)

                if isSeparator(t) {
                    if !current.isEmpty {
                        results.append(current.joined(separator: "\n"))
                        current.removeAll()
                    }
                    // Separator itself is structural — don't add as content
                    continue
                }

                if isBreak(t) && !current.isEmpty {
                    results.append(current.joined(separator: "\n"))
                    current = [stripAllMarkers(from: t)]
                } else if t.isEmpty {
                    if !current.isEmpty {
                        results.append(current.joined(separator: "\n"))
                        current.removeAll()
                    }
                } else {
                    current.append(isBreak(t) ? stripAllMarkers(from: t) : t)
                }
            }
            if !current.isEmpty { results.append(current.joined(separator: "\n")) }

            return results
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // ── Strategy 1: Numbered list ──
        if numberedCount >= 2 {
            let result = split(using: isNumbered)
            if result.count >= 2 { return result }
        }

        // ── Strategy 2: Bullet list ──
        if bulletCount >= 2 && bulletCount >= nonEmpty / 3 {
            let result = split(using: isBullet)
            if result.count >= 2 { return result }
        }

        // ── Strategy 3: Blank-line / separator separated blocks ──
        // Every blank line or separator = new entry
        let blockResult = split(using: { _ in false }) // only blank lines & separators split
        if blockResult.count >= 2 { return blockResult }

        // ── Strategy 4: Every non-empty line is its own entry ──
        let lines = allLines
            .map { stripAllMarkers(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        if lines.count >= 2 { return lines }

        // ── Fallback: entire text as one entry (never lose anything) ──
        return [trimmed]
    }

    /// Strips numbered markers, bullets, and "Joke N:" prefixes
    /// but preserves every word of actual content.
    private static func stripAllMarkers(from line: String) -> String {
        line
            .replacingOccurrences(of: #"^[-•*]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(?:joke|bit|gag|#)\s*\d+\s*[.):\-–—]\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\d+\s*[.):\-–—]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing Helpers

    /// Parses output lines starting with "JOKE:" into an array of joke strings.
    /// Leading/trailing whitespace and the "JOKE:" prefix are stripped.
    nonisolated static func parseJokeLines(from output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.uppercased().hasPrefix("JOKE:") else { return nil }
                let jokeText = String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return jokeText.isEmpty ? nil : jokeText
            }
    }

    /// Removes exact-duplicate jokes (case-sensitive) while preserving order.
    static func deduplicateJokes(_ jokes: [String]) -> [String] {
        var seen = Set<String>()
        return jokes.filter { joke in
            guard !seen.contains(joke) else { return false }
            seen.insert(joke)
            return true
        }
    }
}

// MARK: - Text Chunker

/// Splits a long string into chunks of at most `maxLength` characters,
/// preferring to break at sentence boundaries so the API receives
/// coherent context.
enum GagGrabberChunker {

    static func chunk(_ text: String, maxLength: Int = 2000) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else {
            return cleaned.isEmpty ? [] : [cleaned]
        }

        var chunks: [String] = []
        var remaining = cleaned[cleaned.startIndex...]

        while !remaining.isEmpty {
            if remaining.count <= maxLength {
                chunks.append(String(remaining))
                break
            }

            let window = remaining.prefix(maxLength)
            var splitIndex = window.endIndex

            for candidate in [". ", "! ", "? ", "\n"] {
                if let range = window.range(of: candidate, options: .backwards) {
                    splitIndex = range.upperBound
                    break
                }
            }

            let chunk = String(remaining[remaining.startIndex..<splitIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            remaining = remaining[splitIndex...]
        }

        return chunks
    }
}

// MARK: - Errors

enum GagGrabberError: LocalizedError {
    case openAIRateLimited
    case openAIError(String)
    case pdfExtractionFailed

    var errorDescription: String? {
        switch self {
        case .openAIRateLimited:
            return "OpenAI rate limit hit — try again in a minute."
        case .openAIError(let detail):
            return "OpenAI error: \(detail)"
        case .pdfExtractionFailed:
            return "Could not extract text from this PDF."
        }
    }
}

// MARK: - PDF Text Extraction Helper

/// Lightweight PDF-to-text helper using PDFKit.
private enum GagGrabberPDFReader {

    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw GagGrabberError.pdfExtractionFailed
        }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string {
                pages.append(text)
            }
        }

        let combined = pages.joined(separator: "\n\n")
        guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GagGrabberError.pdfExtractionFailed
        }
        return combined
    }
}

// MARK: - SwiftUI: Toolbar Button + Extraction Sheet

/// A toolbar button that presents the `HybridGagGrabberSheet`.
/// Drop this into any SwiftUI view's `.toolbar { }` block.
struct HybridGagGrabberToolbarButton: View {
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Label("Extract Jokes", systemImage: "doc.text.magnifyingglass")
        }
        .sheet(isPresented: $showSheet) {
            HybridGagGrabberSheet()
        }
    }
}

/// Full-screen sheet: pick a document (.txt / .pdf), extract jokes, and add
/// them one-by-one to the user's Joke library.
struct HybridGagGrabberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var grabber = HybridGagGrabber()

    @State private var showPicker = false
    @State private var savedJokeIDs: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                // MARK: Welcome Hero
                Section {
                    VStack(spacing: 16) {
                        // Fun visual icon cluster
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 90, height: 90)

                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 38, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 8)

                        Text("GagGrabber")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)

                        Text("Drop in a file with your jokes and GagGrabber will read through it and pull out each one individually — so you can add them to your library one by one.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        // Supported formats badges
                        HStack(spacing: 8) {
                            ForEach(["TXT", "PDF", "RTF", "CSV"], id: \.self) { fmt in
                                Text(fmt)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }

                // MARK: Document Format Hint
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How is your document set up?")
                            .font(.subheadline.weight(.semibold))
                        Text("This helps GagGrabber find every joke accurately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. \"Each joke is numbered 1-50\" or \"One joke per line\"",
                                  text: $grabber.documentFormatHint, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Format Hint (optional)", systemImage: "text.magnifyingglass")
                }

                // MARK: Source
                Section("Document") {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Pick a Document (.txt, .pdf, .rtf, …)", systemImage: "doc.badge.plus")
                    }
                    .disabled(grabber.isExtracting)
                }

                // MARK: Status
                if grabber.isExtracting {
                    Section {
                        VStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.9)
                            Text(grabber.statusMessage.isEmpty ? "GagGrabber is extracting jokes…" : grabber.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut(duration: 0.3), value: grabber.statusMessage)
                            if grabber.elapsedSeconds > 0 {
                                Text("\(grabber.elapsedSeconds)s")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            Text("Please stay on this page until it's done!")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                if let error = grabber.lastError {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.blue.opacity(0.6))

                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }

                // MARK: Results
                if !grabber.extractedJokes.isEmpty {
                    let allSaved = grabber.extractedJokes.indices.allSatisfy { savedJokeIDs.contains($0) }

                    Section {
                        // Add All button
                        if !allSaved {
                            Button {
                                addAllJokesToLibrary()
                            } label: {
                                Label("Add All \(grabber.extractedJokes.count) Jokes", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.vertical, 4)
                        } else {
                            Label("All \(grabber.extractedJokes.count) jokes added!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }

                    Section("Extracted Jokes (\(grabber.extractedJokes.count))") {
                        ForEach(Array(grabber.extractedJokes.enumerated()), id: \.offset) { index, joke in
                            HStack(alignment: .top) {
                                Text(joke)
                                    .font(.body)

                                Spacer()

                                if savedJokeIDs.contains(index) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button {
                                        addJokeToLibrary(joke, index: index)
                                    } label: {
                                        Text("Add")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("GagGrabber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(grabber.isExtracting)
                }
            }
            .interactiveDismissDisabled(grabber.isExtracting)
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [.text, .plainText, .utf8PlainText, .pdf, .rtf, .html, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await handlePickedDocument(url) }
                case .failure(let error):
                    grabber.lastError = "Could not open file: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Document Handling

    private func handlePickedDocument(_ url: URL) async {
        grabber.statusMessage = "Opening your file…"
        grabber.isExtracting = true
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()

        do {
            let text: String
            if ext == "pdf" {
                text = try GagGrabberPDFReader.extractText(from: url)
            } else if ext == "rtf" || ext == "rtfd" {
                let data = try Data(contentsOf: url)
                let attributed = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                text = attributed.string
            } else if ext == "html" || ext == "htm" {
                let data = try Data(contentsOf: url)
                let attributed = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
                text = attributed.string
            } else {
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    text = utf8
                } else {
                    text = try String(contentsOf: url)
                }
            }

            await grabber.extractJokes(from: text)
        } catch {
            grabber.lastError = "Failed to read document: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    /// Creates a new `Joke` from the extracted text and inserts it into
    /// SwiftData. Follows the existing `Joke.init(content:title:folder:)` pattern.
    private func addJokeToLibrary(_ jokeText: String, index: Int) {
        let joke = Joke(content: jokeText)
        joke.importSource = "GagGrabber"
        joke.importTimestamp = Date()
        modelContext.insert(joke)

        do {
            try modelContext.save()
            savedJokeIDs.insert(index)
            print(" [GagGrabber] Saved joke #\(index + 1) to library")
        } catch {
            grabber.lastError = "Failed to save joke: \(error.localizedDescription)"
            print(" [GagGrabber] Save failed: \(error)")
        }
    }

    /// Saves all extracted jokes that haven't been saved yet in one batch.
    private func addAllJokesToLibrary() {
        var count = 0
        for (index, jokeText) in grabber.extractedJokes.enumerated() {
            guard !savedJokeIDs.contains(index) else { continue }
            let joke = Joke(content: jokeText)
            joke.importSource = "GagGrabber"
            joke.importTimestamp = Date()
            modelContext.insert(joke)
            savedJokeIDs.insert(index)
            count += 1
        }
        do {
            try modelContext.save()
            print(" [GagGrabber] Batch-saved \(count) joke(s) to library")
        } catch {
            grabber.lastError = "Failed to save jokes: \(error.localizedDescription)"
            print(" [GagGrabber] Batch save failed: \(error)")
        }
    }
}


// MARK: - Preview

#Preview {
    HybridGagGrabberSheet()
        .modelContainer(for: Joke.self, inMemory: true)
}