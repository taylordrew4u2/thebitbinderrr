//
//  RoastJoke.swift
//  thebitbinder
//
//  A single roast joke written for a specific person (RoastTarget).
//

import Foundation
import SwiftData

@Model
final class RoastJoke: Identifiable {
    var id: UUID = UUID()
    var content: String = ""
    var title: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    // Soft-delete (trash) support
    var isDeleted: Bool = false
    var deletedDate: Date?

    /// The person this roast is about
    @Relationship(deleteRule: .nullify)
    var target: RoastTarget?

    init(content: String, title: String = "", target: RoastTarget? = nil) {
        self.content = content
        self.title = title.isEmpty ? KeywordTitleGenerator.title(from: content) : title
        self.target = target
    }

    // MARK: - Trash Helpers

    /// Moves this roast joke to trash. Use instead of modelContext.delete() for recoverability.
    func moveToTrash() {
        isDeleted = true
        deletedDate = Date()
        dateModified = Date()
    }

    func restoreFromTrash() {
        isDeleted = false
        deletedDate = nil
        dateModified = Date()
    }
}
