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
final class RoastTarget {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var photoData: Data?
    var dateCreated: Date = Date()
    var dateModified: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \RoastJoke.target)
    var jokes: [RoastJoke]?

    /// Convenience: sorted jokes, newest first
    var sortedJokes: [RoastJoke] {
        (jokes ?? []).sorted { $0.dateCreated > $1.dateCreated }
    }

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
