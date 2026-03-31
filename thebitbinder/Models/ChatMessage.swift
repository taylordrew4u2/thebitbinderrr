//
//  ChatMessage.swift
//  thebitbinder
//
//  Created by Taylor Drew on 2/20/26.
//

import Foundation
import SwiftData

/// Persisted chat message — kept in the SwiftData schema for backward
/// compatibility. New chat UI code should use `ChatBubbleMessage` (below)
/// to avoid inserting ephemeral messages into the persistent store.
@Model
final class ChatMessage: Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var isUser: Bool = false
    var timestamp: Date = Date()
    var conversationId: String = ""
    
    init(text: String, isUser: Bool, conversationId: String = UUID().uuidString) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.timestamp = Date()
        self.conversationId = conversationId
    }
}

// MARK: - View-Only Chat Message

/// Lightweight, non-persisted chat message for the BitBuddy chat UI.
/// Using this instead of the @Model `ChatMessage` prevents ephemeral
/// conversation turns from being written to the SwiftData store (and
/// subsequently synced to CloudKit), then immediately wiped on dismiss.
struct ChatBubbleMessage: Identifiable {
    let id: UUID = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date = Date()
    let conversationId: String

    init(text: String, isUser: Bool, conversationId: String = UUID().uuidString) {
        self.text = text
        self.isUser = isUser
        self.conversationId = conversationId
    }
}
