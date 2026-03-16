//
//  BitBuddyAIChatView.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import SwiftUI
import SwiftData

/// Full-screen AI chat view accessed from the side menu
struct BitBuddyAIChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Joke.dateCreated, order: .reverse) private var jokes: [Joke]
    @StateObject private var bitBuddy = BitBuddyService.shared
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    @StateObject private var authService = AuthService.shared
    @State private var messages: [ChatMessage] = []
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
        .toolbarBackground(roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.paperCream, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(roastMode ? .dark : .light, for: .navigationBar)
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
            bitBuddy.registerJokeDataProvider {
                jokes.prefix(25).map {
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
                Text(roastMode ? "Ready to Roast?" : "Hey, Comedian!")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                
                Text("Ask me anything about your comedy routine, joke ideas, or how to organize your material.")
                    .font(.system(size: 15, design: .serif))
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Suggestion chips
            VStack(spacing: 8) {
                suggestionChip("Help me write a joke about...")
                suggestionChip("How can I improve my set?")
                suggestionChip("Organize my jokes by theme")
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
        } label: {
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundColor(roastMode ? .white.opacity(0.9) : AppTheme.Colors.inkBlack)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(roastMode ? AppTheme.Colors.roastAccent.opacity(0.3) : AppTheme.Colors.inkBlue.opacity(0.2), lineWidth: 1)
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
        
        let userMessage = ChatMessage(text: message, isUser: true, conversationId: conversationId)
        messages.append(userMessage)
        inputText = ""
        
        Task {
            do {
                let response = try await bitBuddy.sendMessage(message)
                let aiMessage = ChatMessage(text: response, isUser: false, conversationId: conversationId)
                await MainActor.run {
                    messages.append(aiMessage)
                }
            } catch {
                let errorMsg = ChatMessage(text: "Sorry, I encountered an error. Please try again.", isUser: false, conversationId: conversationId)
                await MainActor.run {
                    messages.append(errorMsg)
                }
            }
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    let roastMode: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                // AI Avatar
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
        BitBuddyAIChatView()
    }
}
