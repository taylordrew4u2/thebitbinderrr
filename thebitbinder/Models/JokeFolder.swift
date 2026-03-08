//
//  JokeFolder.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class JokeFolder {
    var id: UUID = UUID()
    var name: String = ""
    var dateCreated: Date = Date()
    var isRecentlyAdded: Bool = false  // Special marker for "Recently Added" folder
    @Relationship(deleteRule: .nullify, inverse: \Joke.folder) var jokes: [Joke]?
    
    init(name: String, isRecentlyAdded: Bool = false) {
        self.id = UUID()
        self.name = name
        self.dateCreated = Date()
        self.isRecentlyAdded = isRecentlyAdded
    }
}
