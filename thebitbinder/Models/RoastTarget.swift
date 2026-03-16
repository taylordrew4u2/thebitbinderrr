//
//  RoastTarget.swift
//  thebitbinder
//
//  A person you're writing roast jokes about.
//  Each target has a name, optional photo, notes,
//  and a collection of roast jokes written for them.
//

import Foundation
import SwiftData

@Model
final class RoastTarget: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    @Relationship(deleteRule: .cascade)
    var jokes: [RoastJoke]?

    /// Convenience: sorted jokes, newest first
    @Transient
    var sortedJokes: [RoastJoke] {
        (jokes ?? []).sorted { $0.dateCreated > $1.dateCreated }
    }

    @Transient
    var jokeCount: Int {
        jokes?.count ?? 0
    }

    init(name: String, notes: String = "", photoData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.photoData = photoData
        self.dateCreated = Date()
        self.dateModified = Date()
    }
}
