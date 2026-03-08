//
//  SetList.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class SetList {
    var id: UUID = UUID()
    var name: String = ""
    var dateCreated: Date = Date()
    var dateModified: Date = Date()
    
    // Store UUIDs as a comma-separated string to avoid SwiftData Array<UUID> issues
    private var jokeIDsString: String = ""
    
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
    
    init(name: String, jokeIDs: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
        self.jokeIDsString = jokeIDs.map { $0.uuidString }.joined(separator: ",")
    }
}
