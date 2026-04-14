//
//  JokeComponents.swift
//  thebitbinder
//
//  Joke-related UI components using native iOS design patterns.
//

import SwiftUI
import SwiftData

// MARK: - Joke Card View (Grid)

struct JokeCardView: View {
    let joke: Joke
    var scale: CGFloat = 1.0
    var roastMode: Bool = false
    var showFullContent: Bool = true
    
    private var isHit: Bool { joke.isHit }
    private var isOpenMic: Bool { joke.isOpenMic }
    
    var body: some View {
        HStack(spacing: 0) {
            // Hit / Open Mic accent strip
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isHit ? Color.blue : (isOpenMic ? Color.blue : .clear))
                .frame(width: 3)
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                // Header: Title + Hit / Open Mic indicator
                HStack(alignment: .top, spacing: 6) {
                    Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Spacer(minLength: 4)
                    
                    if isOpenMic {
                        Image(systemName: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if isHit {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                // Content preview
                if showFullContent {
                    Text(joke.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                        .lineSpacing(2)
                }
                
                Spacer(minLength: 0)
                
                // Footer: Date + folder indicator
                HStack(spacing: 6) {
                    Text(joke.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    
                    Spacer()
                    
                    if let folders = joke.folders, !folders.isEmpty {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(UIColor.quaternaryLabel))
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Joke Row View (List)

struct JokeRowView: View {
    let joke: Joke
    var roastMode: Bool = false
    var showFullContent: Bool = true
    
    private var isHit: Bool { joke.isHit }
    private var isOpenMic: Bool { joke.isOpenMic }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Hit / Open Mic accent strip
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isHit ? Color.blue : (isOpenMic ? Color.blue : .clear))
                .frame(width: 3, height: showFullContent ? 36 : 20)
                .padding(.top, 2)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if isOpenMic {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    if isHit {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                if showFullContent {
                    Text(joke.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 6) {
                    Text(joke.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                    
                    if let folders = joke.folders, let first = folders.first {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                        Text(first.name)
                            .font(.caption)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Folder Chip

struct FolderChip: View {
    let name: String
    var icon: String = "folder.fill"
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            haptic(.selection)
            action()
        }) {
            Text(name)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? (roastMode ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.accentColor))
                        : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
                )
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hits Chip

struct TheHitsChip: View {
    let count: Int
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            haptic(.selection)
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text("Hits")
                    .font(.subheadline.weight(.semibold))
                
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.blue)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.blue)
                    : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
            )
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Open Mic Chip

struct OpenMicChip: View {
    let count: Int
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            haptic(.selection)
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .blue)
                
                Text("Open Mic")
                    .font(.subheadline.weight(.semibold))
                
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.blue)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.blue)
                    : AnyShapeStyle(Color(UIColor.tertiarySystemFill))
            )
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Jokes Empty State

struct JokesEmptyState: View {
    var roastMode: Bool = false
    var hasFilter: Bool = false
    var onAddJoke: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame" : "text.quote",
            title: hasFilter ? "No jokes here" : (roastMode ? "No roasts yet" : "No jokes yet"),
            subtitle: hasFilter
                ? "Try a different filter or search term"
                : (roastMode ? "Add your first roast target to start" : "Start writing your first joke or import from files"),
            actionTitle: hasFilter ? nil : (roastMode ? "Add Target" : "Add Joke"),
            action: onAddJoke,
            roastMode: roastMode
        )
    }
}

// MARK: - Import Progress Card

struct ImportProgressCard: View {
    let importFileCount: Int
    let importFileIndex: Int
    let importStatusMessage: String
    let importedJokeNames: [String]
    var roastMode: Bool = false
    
    @State private var startDate = Date()
    
    private static let importTips = [
        "Typed text extracts better than handwriting",
        "One joke per paragraph gets the best results",
        "PDFs with clear text work great",
        "Good lighting helps photo imports",
        "High-contrast pages scan best",
    ]
    
    private func tipIndex(for date: Date) -> Int {
        let elapsed = date.timeIntervalSince(startDate)
        return Int(elapsed / 5.0)
    }
    
    private var currentStage: ImportStage {
        let lower = importStatusMessage.lowercased()
        if lower.contains("found") { return .finishing }
        if lower.contains("extract") || lower.contains("gaggrabber") { return .extracting }
        if lower.contains("scan") || lower.contains("analyz") || lower.contains("loading") { return .reading }
        return .analyzing
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress indicator
            ProgressView()
                .scaleEffect(1.2)
            
            // Title
            Text(currentStage.title)
                .font(.headline)
            
            // Stage indicators
            HStack(spacing: 4) {
                ForEach(ImportStage.allCases, id: \.self) { stage in
                    stagePill(stage)
                }
            }
            
            // Progress bar
            VStack(spacing: 8) {
                if importFileCount > 1 {
                    Text("File \(importFileIndex) of \(importFileCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: Double(importFileIndex), total: Double(max(1, importFileCount)))
                    .tint(roastMode ? .orange : .accentColor)
                
                Text(importStatusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Recent imports
            if !importedJokeNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found so far:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(importedJokeNames.suffix(3), id: \.self) { name in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Rotating tip
            TimelineView(.periodic(from: .now, by: 5.0)) { context in
                let currentTipIndex = tipIndex(for: context.date)
                Text(Self.importTips[currentTipIndex % Self.importTips.count])
                    .font(.caption)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .multilineTextAlignment(.center)
                    .id(currentTipIndex)
                    .animation(.easeInOut(duration: 0.3), value: currentTipIndex)
            }
        }
        .padding(20)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func stagePill(_ stage: ImportStage) -> some View {
        let isActive = stage == currentStage
        let isComplete = stage.rawValue < currentStage.rawValue
        
        return HStack(spacing: 2) {
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
            }
            Text(stage.shortLabel)
                .font(.caption2)
                .fontWeight(isActive ? .semibold : .regular)
        }
        .foregroundColor(
            isActive ? .white : (isComplete ? .blue : .secondary)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            isActive
                ? AnyShapeStyle(Color.accentColor)
                : (isComplete
                    ? AnyShapeStyle(Color.blue.opacity(0.12))
                    : AnyShapeStyle(Color(UIColor.tertiarySystemFill)))
        )
        .clipShape(Capsule())
    }
}

// MARK: - Import Stage

enum ImportStage: Int, CaseIterable {
    case analyzing = 0
    case reading = 1
    case extracting = 2
    case finishing = 3
    
    var title: String {
        switch self {
        case .analyzing: return "Analyzing File..."
        case .reading: return "Reading Content..."
        case .extracting: return "Extracting..."
        case .finishing: return "Almost Done..."
        }
    }
    
    var shortLabel: String {
        switch self {
        case .analyzing: return "Analyze"
        case .reading: return "Read"
        case .extracting: return "Extract"
        case .finishing: return "Finish"
        }
    }
}

// MARK: - View Mode Enum

enum JokesViewMode: String, CaseIterable {
    case list = "List"
    case grid = "Grid"
    
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

// MARK: - Previews

#Preview("Joke Card") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        JokeCardView(joke: Joke(content: "Why did the chicken cross the road? To get to the other side!", title: "Classic Chicken"))
        JokeCardView(joke: {
            let j = Joke(content: "I told my wife she was drawing her eyebrows too high. She looked surprised.", title: "Eyebrow Joke")
            j.isHit = true
            return j
        }())
    }
    .padding()
}

#Preview("Joke Row") {
    List {
        JokeRowView(joke: Joke(content: "Why did the chicken cross the road? To get to the other side!", title: "Classic Chicken"))
        JokeRowView(joke: {
            let j = Joke(content: "I told my wife she was drawing her eyebrows too high. She looked surprised.", title: "Eyebrow Joke")
            j.isHit = true
            return j
        }())
    }
    .listStyle(.insetGrouped)
}