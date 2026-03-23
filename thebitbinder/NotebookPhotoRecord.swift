//
//  NotebookPhotoRecord.swift
//  thebitbinder
//
//  Model for storing notebook page photos
//

import Foundation
import SwiftData

@Model
final class NotebookPhotoRecord: Identifiable {
    var id: UUID = UUID()
    var notes: String = ""  // Renamed from 'caption' per CD_NotebookPhotoRecord schema
    @Attribute(.externalStorage) var imageData: Data?  // Changed from fileURL to imageData (BYTES) per schema
    var dateAdded: Date = Date()  // Renamed from 'createdAt' per CD_NotebookPhotoRecord schema

    // Soft-delete (trash) support
    var isDeleted: Bool = false
    var deletedDate: Date?

    init(notes: String, imageData: Data? = nil) {
        self.id = UUID()
        self.notes = notes
        self.imageData = imageData
        self.dateAdded = Date()
    }

    // MARK: - Trash Helpers

    /// Moves this photo to trash. The imageData is kept until permanent deletion.
    func moveToTrash() {
        isDeleted = true
        deletedDate = Date()
    }

    func restoreFromTrash() {
        isDeleted = false
        deletedDate = nil
    }
}
