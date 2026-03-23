//
//  Recording.swift
//  thebitbinder
//
//  Created by Taylor Drew on 12/2/25.
//

import Foundation
import SwiftData

@Model
final class Recording: Identifiable {
    var id: UUID = UUID()
    var title: String = ""  // Renamed from 'name' to match CD_Recording schema
    var dateCreated: Date = Date()
    var duration: TimeInterval = 0.0
    var fileURL: String = ""
    var transcription: String?
    var isProcessed: Bool = false  // Added per CD_Recording schema

    // Soft-delete (trash) support
    var isDeleted: Bool = false
    var deletedDate: Date?

    init(title: String, fileURL: String, duration: TimeInterval = 0) {
        self.id = UUID()
        self.title = title
        self.dateCreated = Date()
        self.duration = duration
        self.fileURL = fileURL
        self.transcription = nil
        self.isProcessed = false
    }

    // MARK: - Trash Helpers

    /// Soft-deletes this recording record. The audio file is NOT deleted here.
    /// Permanent deletion (file + record) must be done explicitly by the caller.
    func moveToTrash() {
        isDeleted = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isDeleted = false
        deletedDate = nil
    }
}
