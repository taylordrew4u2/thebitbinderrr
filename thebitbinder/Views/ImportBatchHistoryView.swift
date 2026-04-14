import SwiftUI
import SwiftData

struct ImportBatchHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImportBatch.importTimestamp, order: .reverse) private var batches: [ImportBatch]
    @State private var selectedBatch: ImportBatch?
    @AppStorage("roastModeEnabled") private var roastMode = false
    
    var body: some View {
        NavigationStack {
            Group {
                if batches.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.08))
                                .frame(width: 100, height: 100)
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(.accentColor.opacity(0.5))
                        }
                        
                        VStack(spacing: 8) {
                            Text("No Import History Yet")
                                .font(.title3.weight(.bold))
                            Text("When you import jokes using GagGrabber, each import will be logged here so you can review what was extracted.")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        VStack(spacing: 6) {
                            Text("Import jokes from the **+** menu:")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                importMethodHint(icon: "doc.text", label: "Files")
                                importMethodHint(icon: "camera.viewfinder", label: "Scan")
                                importMethodHint(icon: "photo", label: "Photos")
                                importMethodHint(icon: "waveform", label: "Audio")
                            }
                        }
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(batches) { batch in
                            Button {
                                selectedBatch = batch
                            } label: {
                                batchRow(batch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedBatch) { batch in
                ImportBatchDetailView(batch: batch)
            }
        }
    }
    
    private func batchRow(_ batch: ImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // File name + timestamp
            HStack(alignment: .top) {
                Image(systemName: fileIcon(for: batch.sourceFileName))
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.sourceFileName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(batch.importTimestamp, style: .relative)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    + Text(" ago")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            
            // Stats chips
            HStack(spacing: 8) {
                statChip(
                    icon: "checkmark.circle.fill",
                    value: "\(batch.totalImportedRecords)",
                    label: "imported",
                    color: .blue
                )
                
                if batch.unresolvedFragmentCount > 0 {
                    statChip(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(batch.unresolvedFragmentCount)",
                        label: "unresolved",
                        color: .blue
                    )
                }
                
                statChip(
                    icon: "square.split.2x1.fill",
                    value: "\(batch.totalSegments)",
                    label: "segments",
                    color: .accentColor
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    private func statChip(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func importMethodHint(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor.opacity(0.6))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "txt", "text", "md": return "doc.text"
        case "doc", "docx", "rtf": return "doc.fill"
        case "jpg", "jpeg", "png", "heic": return "photo"
        default:
            if filename.lowercased().contains("scan") { return "camera.viewfinder" }
            if filename.lowercased().contains("photo") { return "photo.on.rectangle" }
            return "doc"
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
    
    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.lowercased() {
        case "high": return .blue
        case "medium": return .blue
        default: return .red
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Summary card
                Section {
                    VStack(spacing: 16) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 20))
                                    .foregroundColor(.accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(batch.sourceFileName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .lineLimit(1)
                                Text(batch.importTimestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        HStack(spacing: 0) {
                            summaryStatItem(
                                value: "\(batch.totalImportedRecords)",
                                label: "Imported",
                                color: .blue
                            )
                            summaryStatItem(
                                value: "\(batch.unresolvedFragmentCount)",
                                label: "Unresolved",
                                color: batch.unresolvedFragmentCount > 0 ? .blue : .secondary
                            )
                            summaryStatItem(
                                value: "\(batch.totalSegments)",
                                label: "Segments",
                                color: .accentColor
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if !unresolved.isEmpty {
                    Section {
                        ForEach(unresolved) { fragment in
                            UnresolvedFragmentHistoryRow(fragment: fragment)
                        }
                    } header: {
                        Label("Unresolved Fragments", systemImage: "puzzle.piece")
                    }
                }
                
                if !imported.isEmpty {
                    Section {
                        ForEach(imported) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.title.isEmpty ? "Untitled" : record.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(record.confidence.capitalized)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(confidenceColor(record.confidence))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule().fill(confidenceColor(record.confidence).opacity(0.12))
                                        )
                                }
                                
                                Text(record.rawSourceText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                
                                if let page = record.sourcePage {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 10))
                                        Text("Page \(page)")
                                            .font(.system(size: 11))
                                    }
                                    .foregroundColor(.secondary.opacity(0.7))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Label("Imported Jokes (\(imported.count))", systemImage: "text.badge.checkmark")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func summaryStatItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct UnresolvedFragmentHistoryRow: View {
    let fragment: UnresolvedImportFragment
    
    private var confidenceColor: Color {
        switch fragment.confidence.lowercased() {
        case "high": return .blue
        case "medium": return .blue
        default: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fragment.titleCandidate ?? "Recovered Fragment")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    
                    HStack(spacing: 6) {
                        Text(fragment.kind.capitalized)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        if let page = fragment.sourcePage {
                            Text("• Page \(page)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Status + confidence
                VStack(alignment: .trailing, spacing: 4) {
                    Text(fragment.isResolved ? "Resolved" : "Open")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(fragment.isResolved ? .blue : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                (fragment.isResolved ? .blue : Color.blue).opacity(0.12)
                            )
                        )
                    
                    Text(fragment.confidence.capitalized)
                        .font(.system(size: 10))
                        .foregroundColor(confidenceColor)
                }
            }
            
            Text(fragment.text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(.vertical, 4)
    }
}
