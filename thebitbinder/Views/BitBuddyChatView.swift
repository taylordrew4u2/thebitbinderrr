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
    
    @State private var messages: [ChatBubbleMessage] = []
    @State private var inputText = ""
    @State private var conversationId = UUID().uuidString
    @State private var isTyping = false
    @State private var typingMessageId: UUID?
    @State private var displayedText = ""
    
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
                        
                        if isTyping {
                            TypingIndicator(roastMode: roastMode)
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
                    dismiss()
                }
                .foregroundColor(accentColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    messages.removeAll()
                    conversationId = UUID().uuidString
                    typingMessageId = nil
                    displayedText = ""
                    isTyping = false
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
                print(" [BitBuddy→SwiftData] Joke saved via action dispatch")
            } catch {
                print(" [BitBuddy→SwiftData] Failed to save joke: \(error)")
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
                    suggestionChip("Show me The Hits")
                    suggestionChip("How do recordings work?")
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
                // Text field
                HStack {
                    TextField("Ask BitBuddy...", text: $inputText)
                        .font(.body)
                        .foregroundColor(.primary)
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
        // No-op — auth is always available for local-only BitBuddy
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
        
        let userMessage = ChatBubbleMessage(text: message, isUser: true, conversationId: conversationId)
        messages.append(userMessage)
        inputText = ""
        isTyping = true
        
        Task {
            do {
                let response = try await bitBuddy.sendMessage(message)
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
                    try? await Task.sleep(nanoseconds: 35_000_000) // 35ms per word
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
                await MainActor.run {
                    isTyping = false
                    let errorMsg = ChatBubbleMessage(text: "Sorry, I encountered an error. Please try again.", isUser: false, conversationId: conversationId)
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
    @State private var dotOffset: [CGFloat] = [0, 0, 0]
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            BitBuddyAvatar(roastMode: roastMode, size: 32, symbolSize: 14)
            
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .offset(y: dotOffset[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color(UIColor.secondarySystemBackground)
            )
            .cornerRadius(16)
            .cornerRadius(4, corners: [.topRight, .bottomLeft, .bottomRight])
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
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2

            // Background circle
            let bgRect = CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
            let bgCircle = Path(ellipseIn: bgRect)
            context.fill(bgCircle, with: .color(Color(UIColor.secondarySystemBackground)))
            context.stroke(
                bgCircle,
                with: .color(roastMode ? Color.orange.opacity(0.35) : Color.accentColor.opacity(0.2)),
                lineWidth: s * 0.02
            )

            if roastMode {
                drawDevilFace(context: &context, cx: cx, cy: cy, s: s)
            } else {
                drawClownFace(context: &context, cx: cx, cy: cy, s: s)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Clown Face (normal mode)

    private func drawClownFace(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        // --- Hair tufts (blue puffs on sides + top) ---
        let tuftRadius = s * 0.13
        let tuftColor = Color(red: 0.0, green: 0.48, blue: 1.0)
        // Left tuft
        context.fill(
            Path(ellipseIn: CGRect(x: cx - s * 0.42, y: cy - s * 0.18, width: tuftRadius * 2, height: tuftRadius * 2)),
            with: .color(tuftColor)
        )
        // Right tuft
        context.fill(
            Path(ellipseIn: CGRect(x: cx + s * 0.42 - tuftRadius * 2, y: cy - s * 0.18, width: tuftRadius * 2, height: tuftRadius * 2)),
            with: .color(tuftColor)
        )
        // Top tuft
        context.fill(
            Path(ellipseIn: CGRect(x: cx - tuftRadius, y: cy - s * 0.44, width: tuftRadius * 2, height: tuftRadius * 1.8)),
            with: .color(tuftColor)
        )

        // --- Face (cream/white circle) ---
        let faceR = s * 0.32
        let faceRect = CGRect(x: cx - faceR, y: cy - faceR + s * 0.02, width: faceR * 2, height: faceR * 2)
        context.fill(Path(ellipseIn: faceRect), with: .color(Color(red: 1.0, green: 0.95, blue: 0.88)))
        context.stroke(Path(ellipseIn: faceRect), with: .color(Color.black.opacity(0.08)), lineWidth: s * 0.008)

        let faceCY = cy + s * 0.02

        // --- Eyes (white ovals with black pupils) ---
        let eyeW = s * 0.1
        let eyeH = s * 0.12
        let eyeY = faceCY - s * 0.1
        let leftEyeRect = CGRect(x: cx - s * 0.12 - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        let rightEyeRect = CGRect(x: cx + s * 0.12 - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        context.fill(Path(ellipseIn: leftEyeRect), with: .color(.white))
        context.fill(Path(ellipseIn: rightEyeRect), with: .color(.white))
        context.stroke(Path(ellipseIn: leftEyeRect), with: .color(Color.black.opacity(0.3)), lineWidth: s * 0.006)
        context.stroke(Path(ellipseIn: rightEyeRect), with: .color(Color.black.opacity(0.3)), lineWidth: s * 0.006)

        // Pupils
        let pupilR = s * 0.03
        context.fill(
            Path(ellipseIn: CGRect(x: cx - s * 0.12 - pupilR, y: eyeY - pupilR * 0.5, width: pupilR * 2, height: pupilR * 2)),
            with: .color(.black)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: cx + s * 0.12 - pupilR, y: eyeY - pupilR * 0.5, width: pupilR * 2, height: pupilR * 2)),
            with: .color(.black)
        )

        // --- Eyebrows (small arcs above eyes) ---
        var leftBrow = Path()
        leftBrow.move(to: CGPoint(x: cx - s * 0.18, y: eyeY - eyeH * 0.7))
        leftBrow.addQuadCurve(
            to: CGPoint(x: cx - s * 0.06, y: eyeY - eyeH * 0.7),
            control: CGPoint(x: cx - s * 0.12, y: eyeY - eyeH * 1.1)
        )
        context.stroke(leftBrow, with: .color(Color.black.opacity(0.5)), lineWidth: s * 0.012)

        var rightBrow = Path()
        rightBrow.move(to: CGPoint(x: cx + s * 0.06, y: eyeY - eyeH * 0.7))
        rightBrow.addQuadCurve(
            to: CGPoint(x: cx + s * 0.18, y: eyeY - eyeH * 0.7),
            control: CGPoint(x: cx + s * 0.12, y: eyeY - eyeH * 1.1)
        )
        context.stroke(rightBrow, with: .color(Color.black.opacity(0.5)), lineWidth: s * 0.012)

        // --- Blue nose ---
        let noseR = s * 0.065
        context.fill(
            Path(ellipseIn: CGRect(x: cx - noseR, y: faceCY - noseR * 0.3, width: noseR * 2, height: noseR * 2)),
            with: .color(Color(red: 0.0, green: 0.48, blue: 1.0))
        )
        // Nose highlight
        let highlightR = noseR * 0.35
        context.fill(
            Path(ellipseIn: CGRect(x: cx - noseR * 0.4, y: faceCY + noseR * 0.05, width: highlightR, height: highlightR)),
            with: .color(.white.opacity(0.5))
        )

        // --- Big smile (blue arc with white teeth) ---
        let smileY = faceCY + s * 0.1
        let smileW = s * 0.22
        let smileH = s * 0.12

        // Blue lip area
        var smilePath = Path()
        smilePath.move(to: CGPoint(x: cx - smileW, y: smileY))
        smilePath.addQuadCurve(
            to: CGPoint(x: cx + smileW, y: smileY),
            control: CGPoint(x: cx, y: smileY + smileH * 2)
        )
        smilePath.addQuadCurve(
            to: CGPoint(x: cx - smileW, y: smileY),
            control: CGPoint(x: cx, y: smileY + smileH * 0.4)
        )
        context.fill(smilePath, with: .color(Color(red: 0.0, green: 0.4, blue: 0.85)))

        // White teeth stripe
        var teethPath = Path()
        teethPath.move(to: CGPoint(x: cx - smileW * 0.7, y: smileY + s * 0.02))
        teethPath.addQuadCurve(
            to: CGPoint(x: cx + smileW * 0.7, y: smileY + s * 0.02),
            control: CGPoint(x: cx, y: smileY + smileH * 1.2)
        )
        teethPath.addQuadCurve(
            to: CGPoint(x: cx - smileW * 0.7, y: smileY + s * 0.02),
            control: CGPoint(x: cx, y: smileY + smileH * 0.5)
        )
        context.fill(teethPath, with: .color(.white))

        // --- Cheek dots (light blue circles) ---
        let cheekR = s * 0.05
        context.fill(
            Path(ellipseIn: CGRect(x: cx - s * 0.26, y: faceCY + s * 0.02, width: cheekR * 2, height: cheekR * 1.5)),
            with: .color(Color.blue.opacity(0.25))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: cx + s * 0.26 - cheekR * 2, y: faceCY + s * 0.02, width: cheekR * 2, height: cheekR * 1.5)),
            with: .color(Color.blue.opacity(0.25))
        )
    }

    // MARK: - Devil Face (roast mode)

    private func drawDevilFace(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, s: CGFloat) {
        // --- Horns ---
        let hornColor = Color(red: 0.8, green: 0.1, blue: 0.1)
        var leftHorn = Path()
        leftHorn.move(to: CGPoint(x: cx - s * 0.2, y: cy - s * 0.22))
        leftHorn.addLine(to: CGPoint(x: cx - s * 0.32, y: cy - s * 0.44))
        leftHorn.addLine(to: CGPoint(x: cx - s * 0.08, y: cy - s * 0.26))
        leftHorn.closeSubpath()
        context.fill(leftHorn, with: .color(hornColor))

        var rightHorn = Path()
        rightHorn.move(to: CGPoint(x: cx + s * 0.2, y: cy - s * 0.22))
        rightHorn.addLine(to: CGPoint(x: cx + s * 0.32, y: cy - s * 0.44))
        rightHorn.addLine(to: CGPoint(x: cx + s * 0.08, y: cy - s * 0.26))
        rightHorn.closeSubpath()
        context.fill(rightHorn, with: .color(hornColor))

        // --- Face (dark red/maroon circle) ---
        let faceR = s * 0.3
        let faceRect = CGRect(x: cx - faceR, y: cy - faceR + s * 0.04, width: faceR * 2, height: faceR * 2)
        context.fill(Path(ellipseIn: faceRect), with: .color(Color(red: 0.55, green: 0.08, blue: 0.08)))

        let faceCY = cy + s * 0.04

        // --- Eyes (yellow/orange slanted) ---
        let eyeW = s * 0.09
        let eyeH = s * 0.1
        let eyeY = faceCY - s * 0.08
        let leftEyeRect = CGRect(x: cx - s * 0.13 - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        let rightEyeRect = CGRect(x: cx + s * 0.13 - eyeW / 2, y: eyeY - eyeH / 2, width: eyeW, height: eyeH)
        context.fill(Path(ellipseIn: leftEyeRect), with: .color(Color(red: 1.0, green: 0.75, blue: 0.0)))
        context.fill(Path(ellipseIn: rightEyeRect), with: .color(Color(red: 1.0, green: 0.75, blue: 0.0)))

        // Slit pupils
        let slitW = s * 0.015
        let slitH = s * 0.06
        context.fill(
            Path(ellipseIn: CGRect(x: cx - s * 0.13 - slitW / 2, y: eyeY - slitH / 2, width: slitW, height: slitH)),
            with: .color(.black)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: cx + s * 0.13 - slitW / 2, y: eyeY - slitH / 2, width: slitW, height: slitH)),
            with: .color(.black)
        )

        // --- Angry eyebrows (angled down toward center) ---
        var leftBrow = Path()
        leftBrow.move(to: CGPoint(x: cx - s * 0.22, y: eyeY - eyeH * 0.5))
        leftBrow.addLine(to: CGPoint(x: cx - s * 0.06, y: eyeY - eyeH * 0.9))
        context.stroke(leftBrow, with: .color(Color.orange), lineWidth: s * 0.018)

        var rightBrow = Path()
        rightBrow.move(to: CGPoint(x: cx + s * 0.22, y: eyeY - eyeH * 0.5))
        rightBrow.addLine(to: CGPoint(x: cx + s * 0.06, y: eyeY - eyeH * 0.9))
        context.stroke(rightBrow, with: .color(Color.orange), lineWidth: s * 0.018)

        // --- Devious grin ---
        let smileY = faceCY + s * 0.08
        let smileW = s * 0.2
        var grin = Path()
        grin.move(to: CGPoint(x: cx - smileW, y: smileY))
        grin.addQuadCurve(
            to: CGPoint(x: cx + smileW, y: smileY),
            control: CGPoint(x: cx, y: smileY + s * 0.14)
        )
        context.stroke(grin, with: .color(Color.orange), lineWidth: s * 0.015)

        // --- Flame wisps at bottom ---
        let flameColors: [Color] = [
            Color(red: 1.0, green: 0.4, blue: 0.0),
            Color(red: 1.0, green: 0.6, blue: 0.0),
            Color(red: 1.0, green: 0.25, blue: 0.0)
        ]
        let flamePositions: [CGFloat] = [-0.15, 0.0, 0.15]
        for (i, xOff) in flamePositions.enumerated() {
            var flame = Path()
            let fx = cx + s * xOff
            let fy = cy + s * 0.36
            flame.move(to: CGPoint(x: fx - s * 0.04, y: fy + s * 0.06))
            flame.addQuadCurve(
                to: CGPoint(x: fx, y: fy - s * 0.06),
                control: CGPoint(x: fx - s * 0.06, y: fy - s * 0.02)
            )
            flame.addQuadCurve(
                to: CGPoint(x: fx + s * 0.04, y: fy + s * 0.06),
                control: CGPoint(x: fx + s * 0.06, y: fy - s * 0.02)
            )
            flame.closeSubpath()
            context.fill(flame, with: .color(flameColors[i % flameColors.count].opacity(0.7)))
        }
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

#Preview {
    NavigationStack {
        BitBuddyChatView()
            .environmentObject(UserPreferences())
    }
}
