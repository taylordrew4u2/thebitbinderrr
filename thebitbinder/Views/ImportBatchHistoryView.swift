import SwiftUI
import SwiftData

struct ImportBatchHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImportBatch.importTimestamp, order: .reverse) private var batches: [ImportBatch]
    @State private var selectedBatch: ImportBatch?
    
    var body: some View {
        NavigationStack {
            List {
                if batches.isEmpty {
                    ContentUnavailableView(
                        "No Import History",
                        systemImage: "tray",
                        description: Text("Imported files and unresolved fragments will appear here.")
                    )
                } else {
                    ForEach(batches) { batch in
                        Button {
                            selectedBatch = batch
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(batch.sourceFileName)
                                        .font(.headline)
                                    Spacer()
                                    Text(batch.importTimestamp, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                HStack(spacing: 12) {
                                    Label("\(batch.totalImportedRecords)", systemImage: "text.badge.plus")
                                    Label("\(batch.unresolvedFragmentCount)", systemImage: "exclamationmark.bubble")
                                    Label("\(batch.totalSegments)", systemImage: "square.split.2x1")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Import History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedBatch) { batch in
                ImportBatchDetailView(batch: batch)
            }
        }
    }
}

struct ImportBatchDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var batch: ImportBatch
    
    var unresolved: [UnresolvedImportFragment] {
        (batch.unresolvedFragments ?? []).sorted { $0.sourceOrder < $1.sourceOrder }
    }
    
    var imported: [ImportedJokeMetadata] {
        (batch.importedRecords ?? []).sorted { $0.sourceOrder < $1.sourceOrder }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Batch Summary") {
                    LabeledContent("Source File", value: batch.sourceFileName)
                    LabeledContent("Imported Records", value: String(batch.totalImportedRecords))
                    LabeledContent("Unresolved", value: String(batch.unresolvedFragmentCount))
                    LabeledContent("Segments", value: String(batch.totalSegments))
                    LabeledContent("Imported At", value: batch.importTimestamp.formatted(date: .abbreviated, time: .shortened))
                }
                
                if !unresolved.isEmpty {
                    Section("Unresolved Fragments") {
                        ForEach(unresolved) { fragment in
                            UnresolvedFragmentHistoryRow(fragment: fragment)
                        }
                    }
                }
                
                if !imported.isEmpty {
                    Section("Imported Records") {
                        ForEach(imported) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.title)
                                    .font(.headline)
                                Text(record.rawSourceText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(5)
                                HStack(spacing: 10) {
                                    Text(record.confidence.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.Colors.primaryAction.opacity(0.12))
                                        .cornerRadius(6)
                                    if let page = record.sourcePage {
                                        Text("Page \(page)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Import Batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct UnresolvedFragmentHistoryRow: View {
    let fragment: UnresolvedImportFragment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fragment.titleCandidate ?? "Recovered Fragment")
                    .font(.headline)
                Spacer()
                Text(fragment.isResolved ? "Resolved" : "Open")
                    .font(.caption.bold())
                    .foregroundStyle(fragment.isResolved ? .green : .orange)
            }
            Text(fragment.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(6)
            HStack(spacing: 10) {
                Text(fragment.kind.capitalized)
                    .font(.caption2)
                Text(fragment.confidence.capitalized)
                    .font(.caption2)
                if let page = fragment.sourcePage {
                    Text("Page \(page)")
                        .font(.caption2)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
