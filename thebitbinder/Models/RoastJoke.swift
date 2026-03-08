//
//  RoastJoke.swift
//  thebitbinder
//
//  A single roast joke written for a specific person (RoastTarget).
//

import Foundation
import SwiftData

@Model
final class RoastJoke {
    var id: UUID = UUID()
    var content: String = ""
    var title: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    /// The person this roast is about
    var target: RoastTarget?

    init(content: String, title: String = "", target: RoastTarget? = nil) {
        self.content = content
        self.title = title.isEmpty ? "Untitled Roast" : title
        self.target = target
    }
}
