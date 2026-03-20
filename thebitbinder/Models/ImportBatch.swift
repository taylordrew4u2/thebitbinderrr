import Foundation
import SwiftData

@Model
final class ImportBatch: Identifiable {
    var id: UUID = UUID()
    var entityName: String = "ImportBatch"  // Required to match CD_entityName in CloudKit schema
    var sourceFileName: String = ""
    var importTimestamp: Date = Date()
    var totalSegments: Int = 0
    var totalImportedRecords: Int = 0
    var unresolvedFragmentCount: Int = 0
    var highConfidenceBoundaries: Int = 0
    var mediumConfidenceBoundaries: Int = 0
    var lowConfidenceBoundaries: Int = 0
    
    @Relationship(deleteRule: .cascade, inverse: \ImportedJokeMetadata.batch)
    var importedRecords: [ImportedJokeMetadata]?
    
    @Relationship(deleteRule: .cascade, inverse: \UnresolvedImportFragment.batch)
    var unresolvedFragments: [UnresolvedImportFragment]?
    
    init(
        sourceFileName: String,
        importTimestamp: Date = Date(),
        totalSegments: Int,
        totalImportedRecords: Int,
        unresolvedFragmentCount: Int,
        highConfidenceBoundaries: Int,
        mediumConfidenceBoundaries: Int,
        lowConfidenceBoundaries: Int
    ) {
        self.id = UUID()
        self.sourceFileName = sourceFileName
        self.importTimestamp = importTimestamp
        self.totalSegments = totalSegments
        self.totalImportedRecords = totalImportedRecords
        self.unresolvedFragmentCount = unresolvedFragmentCount
        self.highConfidenceBoundaries = highConfidenceBoundaries
        self.mediumConfidenceBoundaries = mediumConfidenceBoundaries
        self.lowConfidenceBoundaries = lowConfidenceBoundaries
    }
}

@Model
final class ImportedJokeMetadata: Identifiable {
    var id: UUID = UUID()
    var jokeID: UUID?
    var title: String = ""
    var rawSourceText: String = ""
    var notes: String = ""
    var confidence: String = "low"
    var sourceOrder: Int = 0
    var sourcePage: Int?
    var tagsString: String = ""
    var parsingFlagsJSON: String = "{}"
    var sourceFilename: String = ""
    var importTimestamp: Date = Date()
    
    var batch: ImportBatch?
    
    var tags: [String] {
        get { tagsString.isEmpty ? [] : tagsString.split(separator: "|").map(String.init) }
        set { tagsString = newValue.joined(separator: "|") }
    }
    
    init(
        jokeID: UUID?,
        title: String,
        rawSourceText: String,
        notes: String,
        confidence: String,
        sourceOrder: Int,
        sourcePage: Int?,
        tags: [String],
        parsingFlagsJSON: String,
        sourceFilename: String,
        importTimestamp: Date = Date(),
        batch: ImportBatch? = nil
    ) {
        self.id = UUID()
        self.jokeID = jokeID
        self.title = title
        self.rawSourceText = rawSourceText
        self.notes = notes
        self.confidence = confidence
        self.sourceOrder = sourceOrder
        self.sourcePage = sourcePage
        self.tagsString = tags.joined(separator: "|")
        self.parsingFlagsJSON = parsingFlagsJSON
        self.sourceFilename = sourceFilename
        self.importTimestamp = importTimestamp
        self.batch = batch
    }
}

@Model
final class UnresolvedImportFragment: Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var normalizedText: String = ""
    var kind: String = "unknown"
    var confidence: String = "low"
    var sourceOrder: Int = 0
    var sourcePage: Int?
    var sourceFilename: String = ""
    var titleCandidate: String?
    var tagsString: String = ""
    var parsingFlagsJSON: String = "{}"
    var createdAt: Date = Date()
    var isResolved: Bool = false
    
    var batch: ImportBatch?
    
    var tags: [String] {
        get { tagsString.isEmpty ? [] : tagsString.split(separator: "|").map(String.init) }
        set { tagsString = newValue.joined(separator: "|") }
    }
    
    init(
        text: String,
        normalizedText: String,
        kind: String,
        confidence: String,
        sourceOrder: Int,
        sourcePage: Int?,
        sourceFilename: String,
        titleCandidate: String?,
        tags: [String],
        parsingFlagsJSON: String,
        createdAt: Date = Date(),
        isResolved: Bool = false,
        batch: ImportBatch? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.normalizedText = normalizedText
        self.kind = kind
        self.confidence = confidence
        self.sourceOrder = sourceOrder
        self.sourcePage = sourcePage
        self.sourceFilename = sourceFilename
        self.titleCandidate = titleCandidate
        self.tagsString = tags.joined(separator: "|")
        self.parsingFlagsJSON = parsingFlagsJSON
        self.createdAt = createdAt
        self.isResolved = isResolved
        self.batch = batch
    }
}
