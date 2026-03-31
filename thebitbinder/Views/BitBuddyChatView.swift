//
//  BitBuddyChatView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import SwiftUI
import SwiftData

/// Full-screen chat view accessed from the side menu
struct BitBuddyChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var userPreferences: UserPreferences
    @Query(sort: \Joke.dateCreated, order: .reverse) private var jokes: [Joke]
    @StateObject private var bitBuddy = BitBuddyService.shared
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @StateObject private var authService = AuthService.shared
    @State private var messages: [ChatBubbleMessage] = []
    @State private var inputText = ""
    @State private var conversationId = UUID().uuidString
    
    private var accentColor: Color {
        roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue
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
                                ChatBubble(message: message, roastMode: roastMode)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastMessage = messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            // Input Area
            inputArea
        }
        .background(roastMode ? AppTheme.Colors.roastBackground : AppTheme.Colors.paperCream)
        .navigationTitle(roastMode ? "🔥 BitBuddy" : "BitBuddy")
        .navigationBarTitleDisplayMode(.inline)
        .bitBinderToolbar(roastMode: roastMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(accentColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    messages.removeAll()
                    conversationId = UUID().uuidString
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
            messages.removeAll()
            bitBuddy.cleanupAudioResources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bitBuddyAddJoke)) { notification in
            guard let jokeText = notification.userInfo?["jokeText"] as? String,
                  !jokeText.isEmpty else { return }
            let newJoke = Joke(content: jokeText)
            modelContext.insert(newJoke)
            do {
                try modelContext.save()
                print("✅ [BitBuddy→SwiftData] Joke saved via action dispatch")
            } catch {
                print("❌ [BitBuddy→SwiftData] Failed to save joke: \(error)")
            }
        }
        .onChange(of: bitBuddy.pendingNavigation) { _, section in
            guard let section else { return }
            guard let appScreen = appScreen(for: section) else { return }
            bitBuddy.clearPendingNavigation()
            // Post navigation then dismiss the sheet so the user lands
            // on the target screen.
            NotificationCenter.default.post(
                name: .navigateToScreen,
                object: nil,
                userInfo: ["screen": appScreen.rawValue]
            )
            dismiss()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    .frame(width: 100, height: 100)
                
                Image(systemName: roastMode ? "flame.fill" : "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        roastMode
                        ? AppTheme.Colors.roastEmberGradient
                        : LinearGradient(colors: [AppTheme.Colors.inkBlue, AppTheme.Colors.inkBlue.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
            }
            
            VStack(spacing: 8) {
                Text(roastMode ? "Ready to Roast?" : "Hey, \(userPreferences.userName)!")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                
                Text("I can help with your jokes, set lists, brainstorms, recordings, imports, and more — all on-device.")
                    .font(.system(size: 15, design: .serif))
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Suggestion chips — one per major section
            VStack(spacing: 8) {
                if roastMode {
                    suggestionChip("🔥 Give me roast lines for a finance bro")
                    suggestionChip("🎯 Create a roast target")
                    suggestionChip("📋 Build a roast set for battle night")
                    suggestionChip("✂️ Shorten this burn")
                } else {
                    suggestionChip("🎭 Analyze this joke: I told my therapist I feel invisible. She said 'Next!'")
                    suggestionChip("📋 Create a set list for tonight")
                    suggestionChip("💡 Give me a premise about dating apps")
                    suggestionChip("⭐ Show me The Hits")
                    suggestionChip("🎙️ How do recordings work?")
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 280, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                        .strokeBorder(
                            roastMode ? AppTheme.Colors.roastAccent.opacity(0.25) : AppTheme.Colors.primaryAction.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(ChipStyle())
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 12) {
                // Text field
                HStack {
                    TextField("Ask BitBuddy...", text: $inputText)
                        .font(.system(size: 16, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(roastMode ? AppTheme.Colors.roastAccent.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                
                // Send button
                Button(action: sendMessage) {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty || bitBuddy.isLoading
                                ? (roastMode ? AppTheme.Colors.roastCard : Color(.systemGray5))
                                : accentColor
                            )
                            .frame(width: 44, height: 44)
                        
                        if bitBuddy.isLoading {
                            ProgressView()
                                .tint(roastMode ? .white : AppTheme.Colors.inkBlack)
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
                .buttonStyle(FABButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.paperCream)
        }
    }
    
    private func handleAppear() {
        if !authService.isAuthenticated {
            Task {
                try? await authService.signInAnonymously()
            }
        }
    }
    
    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        guard !bitBuddy.isLoading else { return }
        
        let userMessage = ChatBubbleMessage(text: message, isUser: true, conversationId: conversationId)
        messages.append(userMessage)
        inputText = ""
        
        Task {
            do {
                let response = try await bitBuddy.sendMessage(message)
                let aiMessage = ChatBubbleMessage(text: response, isUser: false, conversationId: conversationId)
                await MainActor.run {
                    messages.append(aiMessage)
                }
            } catch {
                let errorMsg = ChatBubbleMessage(text: "Sorry, I encountered an error. Please try again.", isUser: false, conversationId: conversationId)
                await MainActor.run {
                    messages.append(errorMsg)
                }
            }
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
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                // BitBuddy Avatar
                ZStack {
                    Circle()
                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: roastMode ? "flame.fill" : "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
                }
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 15, design: .serif))
                    .padding(12)
                    .background(
                        message.isUser
                        ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.inkBlue)
                        : (roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    )
                    .foregroundColor(
                        message.isUser
                        ? .white
                        : (roastMode ? .white.opacity(0.9) : AppTheme.Colors.inkBlack)
                    )
                    .cornerRadius(16)
                    .cornerRadius(message.isUser ? 16 : 4, corners: message.isUser ? [.topLeft, .bottomLeft, .bottomRight] : [.topRight, .bottomLeft, .bottomRight])
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
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

#Preview {
    NavigationStack {
        BitBuddyChatView()
            .environmentObject(UserPreferences())
    }
}
