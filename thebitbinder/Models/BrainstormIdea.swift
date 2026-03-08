//
//  BrainstormIdea.swift
//  thebitbinder
//
//  Created for quick joke brainstorming
//

import Foundation
import SwiftData

@Model
final class BrainstormIdea {
    var id: UUID = UUID()
    var content: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    var colorHex: String = "F5E6D3"  // Store color as hex for variety in grid
    var isVoiceNote: Bool = false  // Track if it was created via voice
    
    init(content: String, colorHex: String = "F5E6D3", isVoiceNote: Bool = false) {
        self.id = UUID()
        self.content = content
        self.dateCreated = Date()
        self.dateModified = Date()
        self.colorHex = colorHex
        self.isVoiceNote = isVoiceNote
    }
    
    // Predefined color palette for sticky notes
    static let noteColors: [String] = [
        "FFF9C4", // Light yellow
        "FFECB3", // Amber
        "FFE0B2", // Orange light
        "F8BBD9", // Pink light
        "E1BEE7", // Purple light
        "C5CAE9", // Indigo light
        "B3E5FC", // Light blue
        "B2DFDB", // Teal light
        "C8E6C9", // Green light
        "DCEDC8", // Light green
    ]
    
    static func randomColor() -> String {
        noteColors.randomElement() ?? "FFF9C4"
    }
}
