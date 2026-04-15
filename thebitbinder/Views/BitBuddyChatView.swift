//
//  BitBuddyChatView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

/// Full-screen chat view accessed from the side menu
struct BitBuddyChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var userPreferences: UserPreferences
    @Query(sort: \Joke.dateCreated, order: .reverse) private var jokes: [Joke]
    @StateObject private var bitBuddy = BitBuddyService.shared
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @State private var messages: [ChatBubbleMessage] = []
    @State private var inputText = ""
    @State private var conversationId = UUID().uuidString
    @State private var isTyping = false
    @State private var typingMessageId: UUID?
    @State private var displayedText = ""
    /// Tracks the active send + typewriter Task so it can be cancelled
    /// when the user sends a new message, resets the conversation, or
    /// dismisses the sheet. Without this, concurrent typewriter Tasks
    /// both write to `displayedText` and produce garbled output.
    @State private var activeResponseTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool
    
    // MARK: - HybridGagGrabber Integration
    @StateObject private var gagGrabber = HybridGagGrabber()
    @State private var showDocumentPicker = false
    @State private var extractedJokeResults: [String] = []
    @State private var savedExtractedJokeIDs: Set<Int> = []
    @State private var extractedFileName: String = ""
    
    private var accentColor: Color {
        roastMode ? .orange : .accentColor
    }

    @ViewBuilder
    private var bitBuddyAvatar: some View {
        BitBuddyAvatar(roastMode: roastMode, size: 100, symbolSize: 42)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages View
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(messages) { message in
                                ChatBubble(
                                    message: message,
                                    roastMode: roastMode,
                                    typingMessageId: typingMessageId,
                                    displayedText: displayedText
                                )
                                .id(message.id)
                            }
                        }
                        
                        // HybridGagGrabber extraction progress
                        if gagGrabber.isExtracting {
                            HStack(alignment: .top, spacing: 8) {
                                BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Extracting jokes from \(extractedFileName)…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(16)
                                .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
                                Spacer(minLength: 60)
                            }
                            .id("extraction-progress")
                        }
                        
                        // HybridGagGrabber extracted jokes results
                        if !extractedJokeResults.isEmpty {
                            extractedJokesSection
                                .id("extracted-jokes")
                        }
                        
                        if isTyping {
                            TypingIndicator(roastMode: roastMode, statusMessage: bitBuddy.statusMessage)
                                .id("typing-indicator")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isTyping) {
                    if isTyping {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: displayedText) {
                    scrollToBottom(proxy: proxy)
                }
            }
            .frame(maxHeight: .infinity)
            
            // Input Area
            inputArea
        }
        .background(Color(UIColor.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    // Dismiss keyboard first to avoid stale input session errors
                    isInputFocused = false
                    // Brief delay lets keyboard frame animation complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismiss()
                    }
                }
                .foregroundColor(accentColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeResponseTask?.cancel()
                    activeResponseTask = nil
                    messages.removeAll()
                    conversationId = UUID().uuidString
                    typingMessageId = nil
                    displayedText = ""
                    isTyping = false
                    extractedJokeResults.removeAll()
                    savedExtractedJokeIDs.removeAll()
                    bitBuddy.startNewConversation()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .foregroundColor(accentColor)
                .disabled(messages.isEmpty)
            }
        }
        .tint(accentColor)
        .onAppear {
            handleAppear()
            // Provide larger context for local analysis (200 items)
            bitBuddy.registerJokeDataProvider {
                jokes.prefix(200).map {
                    BitBuddyJokeSummary(
                        id: $0.id,
                        title: $0.title,
                        content: $0.content,
                        tags: $0.tags,
                        dateCreated: $0.dateCreated
                    )
                }
            }
        }
        .onDisappear {
            isInputFocused = false
            activeResponseTask?.cancel()
            activeResponseTask = nil
            typingMessageId = nil
            displayedText = ""
            isTyping = false
            messages.removeAll()
            extractedJokeResults.removeAll()
            savedExtractedJokeIDs.removeAll()
            bitBuddy.cleanupAudioResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyAddJoke)) { notification in
            guard let jokeText = notification.userInfo?["jokeText"] as? String,
                  !jokeText.isEmpty else { return }
            let newJoke = Joke(content: jokeText)
            modelContext.insert(newJoke)
            do {
                try modelContext.save()
                print(" [BitBuddy→SwiftData] Joke saved via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save joke: \(error)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyTriggerFileImport)) { _ in
            showDocumentPicker = true
        }
        .sheet(isPresented: $showDocumentPicker) {
            BitBuddyDocumentPicker { urls in
                guard let url = urls.first else { return }
                Task { await handleDocumentPicked(url) }
            }
        }
        .onChange(of: bitBuddy.pendingNavigation) { _, section in
            guard let section else { return }
            guard let appScreen = appScreen(for: section) else { return }
            bitBuddy.clearPendingNavigation()
            // Dismiss keyboard first to prevent stale input sessions
            isInputFocused = false
            // Post navigation then dismiss the sheet so the user lands
            // on the target screen.
            NotificationCenter.default.post(
                name: .navigateToScreen,
                object: nil,
                userInfo: ["screen": appScreen.rawValue]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                dismiss()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                bitBuddyAvatar
            }
            
            VStack(spacing: 8) {
                Text(roastMode ? "Ready to Roast?" : "Hey, \(userPreferences.userName)!")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                Text("I can help with your jokes, set lists, brainstorms, recordings, imports, and more.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Suggestion chips — one per major section
            VStack(spacing: 8) {
                if roastMode {
                    suggestionChip("Give me roast lines for a finance bro")
                    suggestionChip("Create a roast target")
                    suggestionChip("Build a roast set for battle night")
                    suggestionChip("Shorten this burn")
                } else {
                    suggestionChip("Analyze this joke: I told my therapist I feel invisible. She said 'Next!'")
                    suggestionChip("Create a set list for tonight")
                    suggestionChip("Give me a premise about dating apps")
                    suggestionChip("What makes a good punchline?")
                    suggestionChip("How do recordings work?")
                    
                    // File upload suggestion — opens document picker directly
                    Button {
                        showDocumentPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.subheadline)
                            Text("Extract jokes from a file")
                                .font(.subheadline)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 280, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 280, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            roastMode ? Color.orange.opacity(0.25) : Color.accentColor.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                // Document upload button (HybridGagGrabber)
                Button {
                    showDocumentPicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundColor(accentColor.opacity(0.8))
                }
                .disabled(gagGrabber.isExtracting || bitBuddy.isLoading)
                .buttonStyle(.plain)
                
                // Text field
                HStack {
                    TextField("Ask BitBuddy...", text: $inputText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { sendMessage() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(roastMode ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                
                // Send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty || bitBuddy.isLoading
                                ? Color(UIColor.systemGray5)
                                : accentColor
                            )
                            .frame(width: 44, height: 44)
                        
                        if bitBuddy.isLoading {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(
                                    inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? (roastMode ? .white.opacity(0.3) : .gray)
                                    : .white
                                )
                        }
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || bitBuddy.isLoading)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
    }
    
    private func handleAppear() {
        // Greet the user on every fresh conversation
        if messages.isEmpty {
            let greeting = roastMode
                ? "🔥 BitBuddy here — Roast Mode is ON. Give me a target and I'll load the burns."
                : "Hey! I'm BitBuddy, your comedy writing partner. Ask me to analyze a joke, build a set list, brainstorm premises, or anything else — I'm ready when you are."
            let intro = ChatBubbleMessage(text: greeting, isUser: false, conversationId: conversationId)
            messages.append(intro)
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        guard !bitBuddy.isLoading else { return }
        
        // Cancel any in-flight typewriter animation from a previous response.
        // Without this, two Tasks write to `displayedText` simultaneously and
        // the user sees garbled text.
        activeResponseTask?.cancel()
        activeResponseTask = nil
        // If a previous message was mid-typewriter, reveal its full text now
        typingMessageId = nil
        
        let userMessage = ChatBubbleMessage(text: message, isUser: true, conversationId: conversationId)
        messages.append(userMessage)
        inputText = ""
        isTyping = true
        
        activeResponseTask = Task {
            do {
                let response = try await bitBuddy.sendMessage(message)
                
                // Bail out if the Task was cancelled while waiting for the response
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    isTyping = false
                    let aiMessage = ChatBubbleMessage(text: response, isUser: false, conversationId: conversationId)
                    messages.append(aiMessage)
                    typingMessageId = aiMessage.id
                    displayedText = ""
                }
                // Typewriter: reveal word by word
                let words = response.split(separator: " ", omittingEmptySubsequences: false)
                for (index, word) in words.enumerated() {
                    // Check cancellation before each word so we stop quickly
                    // when the user sends a new message or dismisses the sheet.
                    guard !Task.isCancelled else {
                        return
                    }
                    try? await Task.sleep(nanoseconds: 15_000_000) // 15ms per word
                    // Re-check after sleep — cancellation may have fired while
                    // we were waiting. Without this second guard a cancelled
                    // task writes one stale word into displayedText, which
                    // contaminates the *next* response's typewriter output
                    // and produces garbled text with missing or wrong letters.
                    guard !Task.isCancelled else {
                        return
                    }
                    await MainActor.run {
                        if index == 0 {
                            displayedText = String(word)
                        } else {
                            displayedText += " " + String(word)
                        }
                    }
                }
                await MainActor.run {
                    typingMessageId = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isTyping = false
                    let errorMsg = ChatBubbleMessage(text: "Sorry, I encountered an error. Please try again.", isUser: false, conversationId: conversationId)
                    messages.append(errorMsg)
                }
            }
        }
    }
    
    // MARK: - HybridGagGrabber: Extracted Jokes Section
    
    private var extractedJokesSection: some View {
        HStack(alignment: .top, spacing: 8) {
            BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Found \(extractedJokeResults.count) joke\(extractedJokeResults.count == 1 ? "" : "s") in **\(extractedFileName)**")
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                
                if let error = gagGrabber.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                ForEach(Array(extractedJokeResults.enumerated()), id: \.offset) { index, joke in
                    HStack(alignment: .top, spacing: 8) {
                        Text(joke)
                            .font(.callout)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if savedExtractedJokeIDs.contains(index) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.body)
                        } else {
                            Button {
                                saveExtractedJoke(joke, index: index)
                            } label: {
                                Text("Add")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(accentColor)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                }
                
                // Bulk action: add all remaining
                if extractedJokeResults.count > 1,
                   savedExtractedJokeIDs.count < extractedJokeResults.count {
                    Button {
                        saveAllExtractedJokes()
                    } label: {
                        Label("Add All to Library", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
            .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
            
            Spacer(minLength: 20)
        }
    }
    
    // MARK: - HybridGagGrabber: Document Handling
    
    /// Reads a picked document (txt/pdf), runs HybridGagGrabber extraction,
    /// and displays the results inline in the chat.
    private func handleDocumentPicked(_ url: URL) async {
        // Security-scoped resource access — required for files from
        // Files app, iCloud Drive, and third-party file providers.
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        extractedFileName = fileName
        extractedJokeResults = []
        savedExtractedJokeIDs = []
        
        // Add a user-style message to the chat showing the file was selected
        let userMsg = ChatBubbleMessage(
            text: "Extract jokes from \(fileName)",
            isUser: true,
            conversationId: conversationId
        )
        messages.append(userMsg)
        
        let ext = url.pathExtension.lowercased()
        
        do {
            let text: String
            if ext == "pdf" {
                guard let document = PDFDocument(url: url) else {
                    appendErrorMessage("Could not open PDF: \(fileName)")
                    return
                }
                var pages: [String] = []
                for i in 0..<document.pageCount {
                    if let page = document.page(at: i), let content = page.string {
                        pages.append(content)
                    }
                }
                let combined = pages.joined(separator: "\n\n")
                guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    appendErrorMessage("PDF has no extractable text: \(fileName)")
                    return
                }
                text = combined
            } else {
                // Try UTF-8 first, fall back to auto-detected encoding
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    text = utf8
                } else {
                    text = try String(contentsOf: url)
                }
            }
            
            await gagGrabber.extractJokes(from: text, useOpenAI: false)
            
            // Populate results for the in-chat display
            extractedJokeResults = gagGrabber.extractedJokes
            
            if extractedJokeResults.isEmpty {
                let noResultsMsg = ChatBubbleMessage(
                    text: gagGrabber.lastError ?? "No jokes found in \(fileName). The document may not contain recognizable joke content.",
                    isUser: false,
                    conversationId: conversationId
                )
                messages.append(noResultsMsg)
            }
        } catch {
            appendErrorMessage("Failed to read \(fileName): \(error.localizedDescription)")
        }
    }
    
    /// Appends a BitBuddy error message to the chat.
    private func appendErrorMessage(_ text: String) {
        let msg = ChatBubbleMessage(text: text, isUser: false, conversationId: conversationId)
        messages.append(msg)
    }
    
    // MARK: - HybridGagGrabber: Persistence
    
    /// Saves a single extracted joke to the library via SwiftData.
    private func saveExtractedJoke(_ jokeText: String, index: Int) {
        let joke = Joke(content: jokeText)
        joke.importSource = "HybridGagGrabber"
        joke.importTimestamp = Date()
        modelContext.insert(joke)
        
        do {
            try modelContext.save()
            savedExtractedJokeIDs.insert(index)
            print(" [BitBuddy→GagGrabber] Saved extracted joke #\(index + 1) to library")
        } catch {
            print(" [BitBuddy→GagGrabber] Save failed: \(error)")
            appendErrorMessage("Failed to save joke: \(error.localizedDescription)")
        }
    }
    
    /// Saves all un-saved extracted jokes to the library in one batch.
    private func saveAllExtractedJokes() {
        var savedCount = 0
        for (index, jokeText) in extractedJokeResults.enumerated() {
            guard !savedExtractedJokeIDs.contains(index) else { continue }
            
            let joke = Joke(content: jokeText)
            joke.importSource = "HybridGagGrabber"
            joke.importTimestamp = Date()
            modelContext.insert(joke)
            savedExtractedJokeIDs.insert(index)
            savedCount += 1
        }
        
        do {
            try modelContext.save()
            print(" [BitBuddy→GagGrabber] Bulk saved \(savedCount) joke(s) to library")
        } catch {
            print(" [BitBuddy→GagGrabber] Bulk save failed: \(error)")
            appendErrorMessage("Failed to save jokes: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Section → AppScreen Mapping
    
    /// Maps a BitBuddySection to the corresponding AppScreen for navigation.
    private func appScreen(for section: BitBuddySection) -> AppScreen? {
        switch section {
        case .jokes, .roastMode:  return .jokes
        case .brainstorm:         return .brainstorm
        case .setLists:           return .sets
        case .recordings:         return .recordings
        case .notebook:           return .notebookSaver
        case .settings, .sync:    return .settings
        case .help:               return .settings   // Help lives under Settings
        case .importFlow:         return .jokes       // Import lands on Jokes
        case .bitbuddy:           return nil           // Stay in chat
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatBubbleMessage
    let roastMode: Bool
    var typingMessageId: UUID? = nil
    var displayedText: String = ""
    
    private var isBeingTyped: Bool {
        typingMessageId == message.id
    }
    
    private var visibleText: String {
        if isBeingTyped {
            return displayedText
        }
        return message.text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(visibleText)
                        .font(.body)
                    
                    if isBeingTyped {
                        Text("|")
                            .font(.body.weight(.light))
                            .opacity(0.6)
                            .blinking()
                    }
                }
                .padding(12)
                .background(
                    message.isUser
                    ? (roastMode ? Color.orange : Color.accentColor)
                    : Color(UIColor.secondarySystemBackground)
                )
                .foregroundColor(
                    message.isUser
                    ? .white
                    : .primary
                )
                .cornerRadius(16)
                .cornerRadius(message.isUser ? 16 : 4, corners: message.isUser ? [.topLeft, .bottomLeft, .bottomRight] : [.topRight, .bottomLeft, .bottomRight])
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 60)
            } else {
                // User avatar placeholder (optional)
            }
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let roastMode: Bool
    var statusMessage: String = ""
    @State private var dotOffset: [CGFloat] = [0, 0, 0]
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                            .offset(y: dotOffset[index])
                    }
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color(UIColor.secondarySystemBackground)
            )
            .cornerRadius(16)
            .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
            .animation(.easeInOut(duration: 0.3), value: statusMessage)
            .onAppear {
                for i in 0..<3 {
                    withAnimation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15)
                    ) {
                        dotOffset[i] = -5
                    }
                }
            }
            
            Spacer(minLength: 60)
        }
    }
}

struct BitBuddyAvatar: View {
    let roastMode: Bool
    let size: CGFloat
    let symbolSize: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            // 100×100 design space, scaled to square frame
            let s = min(w, h) / 100.0
            let ox = (w - 100.0 * s) / 2.0
            let oy = (h - 100.0 * s) / 2.0

            func r(_ v: CGFloat) -> CGFloat { v * s }

            let blue: Color = .blue
            let lineW = max(1.0, s * 2.4)

            // ====== SMILEY FACE WITH CLOWN NOSE — ALL BLUE ======

            // --- Face circle (stroked outline) ---
            var face = Path()
            face.addEllipse(in: CGRect(x: ox + 8 * s, y: oy + 8 * s,
                                       width: r(84), height: r(84)))
            context.stroke(face, with: .color(blue), lineWidth: lineW)

            // --- Eyes (filled dots) ---
            var leftEye = Path()
            leftEye.addEllipse(in: CGRect(x: ox + 32 * s - r(4.5),
                                          y: oy + 36 * s - r(4.5),
                                          width: r(9), height: r(9)))
            context.fill(leftEye, with: .color(blue))

            var rightEye = Path()
            rightEye.addEllipse(in: CGRect(x: ox + 68 * s - r(4.5),
                                           y: oy + 36 * s - r(4.5),
                                           width: r(9), height: r(9)))
            context.fill(rightEye, with: .color(blue))

            // --- Clown nose (filled, prominent round nose) ---
            var nose = Path()
            nose.addEllipse(in: CGRect(x: ox + 50 * s - r(7),
                                       y: oy + 48 * s - r(6.5),
                                       width: r(14), height: r(13)))
            context.fill(nose, with: .color(blue))

            // --- Smile (wide arc) ---
            var smile = Path()
            smile.move(to: CGPoint(x: ox + 28 * s, y: oy + 62 * s))
            smile.addQuadCurve(to: CGPoint(x: ox + 72 * s, y: oy + 62 * s),
                               control: CGPoint(x: ox + 50 * s, y: oy + 82 * s))
            context.stroke(smile, with: .color(blue), lineWidth: lineW)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Blinking Cursor Modifier

struct BlinkingModifier: ViewModifier {
    @State private var visible = true
    
    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

extension View {
    func blinking() -> some View {
        modifier(BlinkingModifier())
    }
}

// MARK: - BitBuddy Document Picker

/// A lightweight UIDocumentPickerViewController wrapper for uploading
/// .txt and .pdf files into BitBuddy for joke extraction via HybridGagGrabber.
private struct BitBuddyDocumentPicker: UIViewControllerRepresentable {
    let completion: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.plainText, .pdf, .utf8PlainText, .text]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        init(completion: @escaping ([URL]) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
    }
}

#Preview {
    NavigationStack {
        BitBuddyChatView()
            .environmentObject(UserPreferences())
    }
}
