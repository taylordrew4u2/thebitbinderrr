//
//  SetList.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class SetList: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    var notes: String = ""  // Added per CD_SetList schema

    // Soft-delete (trash) support
    var isDeleted: Bool = false
    var deletedDate: Date?

    // Store UUIDs as a comma-separated string to avoid SwiftData Array<UUID> issues
    private var jokeIDsString: String = ""
    private var roastJokeIDsString: String = ""
    
    // Computed property to access as [UUID]
    var jokeIDs: [UUID] {
        get {
            guard !jokeIDsString.isEmpty else { return [] }
            return jokeIDsString.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        set {
            jokeIDsString = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }
    
    // Roast joke IDs stored the same way
    var roastJokeIDs: [UUID] {
        get {
            guard !roastJokeIDsString.isEmpty else { return [] }
            return roastJokeIDsString.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        }
        set {
            roastJokeIDsString = newValue.map { $0.uuidString }.joined(separator: ",")
        }
    }
    
    /// Total number of items (regular + roast) in this set
    var totalItemCount: Int {
        jokeIDs.count + roastJokeIDs.count
    }
    
    init(name: String, jokeIDs: [UUID] = [], roastJokeIDs: [UUID] = [], notes: String = "") {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
        self.notes = notes
        self.jokeIDsString = jokeIDs.map { $0.uuidString }.joined(separator: ",")
        self.roastJokeIDsString = roastJokeIDs.map { $0.uuidString }.joined(separator: ",")
    }

    // MARK: - Trash Helpers

    /// Moves this set list to trash. Use instead of modelContext.delete() for recoverability.
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
