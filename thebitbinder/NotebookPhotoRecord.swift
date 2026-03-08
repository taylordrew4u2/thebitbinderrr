import Foundation
import SwiftData

@Model
final class NotebookPhotoRecord: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    var caption: String = ""
    var fileURL: String = ""
    var createdAt: Date = Date()

    init(caption: String, fileURL: String) {
        self.id = UUID()
        self.caption = caption
        self.fileURL = fileURL
        self.createdAt = Date()
    }
}
