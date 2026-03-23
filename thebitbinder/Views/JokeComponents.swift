//
//  JokeComponents.swift
//  thebitbinder
//
//  Extracted joke-related UI components for cleaner architecture
//  Improved visual hierarchy, clearer status/hit indicators, better scanning
//

import SwiftUI
import SwiftData

// MARK: - Improved Joke Card (Grid View)

struct JokeCardView: View {
    let joke: Joke
    var scale: CGFloat = 1.0
    var roastMode: Bool = false
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    
    private var isHit: Bool { joke.isHit }
    private var hasFolder: Bool { joke.folder != nil }
    private var hasTags: Bool { !joke.tags.isEmpty }
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            let padding = max(10, size * 0.08)
            let titleSize = max(11, size * 0.095)
            let bodySize = max(10, size * 0.08)
            let metaSize = max(8, size * 0.06)
            let spacing = max(6, size * 0.05)
            
            VStack(alignment: .leading, spacing: spacing) {
                // Header: Title + Hit badge
                HStack(alignment: .top, spacing: 6) {
                    Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                        .font(.system(size: titleSize, weight: .bold, design: .serif))
                        .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Spacer(minLength: 4)
                    
                    // Hit star badge (top right)
                    if isHit {
                        HitStarBadge(size: max(14, size * 0.1), showBackground: false, roastMode: roastMode)
                    }
                }
                
                // Content preview
                Text(joke.content)
                    .font(.system(size: bodySize))
                    .foregroundColor(roastMode ? .white.opacity(0.75) : AppTheme.Colors.textSecondary)
                    .lineLimit(expandAllJokes ? nil : max(3, Int(size / 28)))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 0)
                
                // Footer: Tags, folder, date
                VStack(alignment: .leading, spacing: 4) {
                    // Tags row (if any)
                    if hasTags && size > 120 {
                        HStack(spacing: 4) {
                            ForEach(joke.tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: max(7, metaSize - 1), weight: .medium))
                                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent.opacity(0.8) : AppTheme.Colors.primaryAction.opacity(0.8))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill((roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.12))
                                    )
                            }
                            if joke.tags.count > 2 {
                                Text("+\(joke.tags.count - 2)")
                                    .font(.system(size: max(7, metaSize - 1)))
                                    .foregroundColor(roastMode ? .white.opacity(0.4) : AppTheme.Colors.textTertiary)
                            }
                        }
                    }
                    
                    // Folder + date row
                    HStack(spacing: 6) {
                        if let folder = joke.folder {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: max(7, metaSize - 1)))
                                Text(folder.name)
                                    .font(.system(size: metaSize, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.primaryAction.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Text(joke.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: metaSize))
                            .foregroundColor(roastMode ? .white.opacity(0.35) : AppTheme.Colors.textTertiary)
                    }
                }
            }
            .padding(padding)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
            )
            .overlay(
                // Subtle hit glow border
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .strokeBorder(
                        isHit 
                            ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold).opacity(0.4)
                            : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .shadow(
                color: isHit 
                    ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold).opacity(0.15)
                    : Color.black.opacity(0.05),
                radius: isHit ? 8 : 4,
                y: 2
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Improved Joke Row (List View)

struct JokeRowView: View {
    let joke: Joke
    var roastMode: Bool = false
    @AppStorage("expandAllJokes") private var expandAllJokes = false
    
    private var isHit: Bool { joke.isHit }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left indicator (hit star or bullet)
            if isHit {
                HitStarBadge(size: 16, showBackground: false, roastMode: roastMode)
                    .frame(width: 20)
            } else {
                Circle()
                    .fill(roastMode ? AppTheme.Colors.roastAccent.opacity(0.5) : AppTheme.Colors.primaryAction.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .frame(width: 20)
                    .padding(.top, 7)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(joke.title.isEmpty ? KeywordTitleGenerator.displayTitle(from: joke.content) : joke.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
                    .lineLimit(1)
                
                // Content preview
                Text(joke.content)
                    .font(.system(size: 14))
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                    .lineLimit(expandAllJokes ? nil : 2)
                    .lineSpacing(2)
                
                // Metadata row
                HStack(spacing: 8) {
                    // Tags (inline, compact)
                    if !joke.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(joke.tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent.opacity(0.8) : AppTheme.Colors.primaryAction.opacity(0.8))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill((roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction).opacity(0.1))
                                    )
                            }
                        }
                    }
                    
                    // Folder
                    if let folder = joke.folder {
                        HStack(spacing: 3) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9))
                            Text(folder.name)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.primaryAction.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Word count (subtle)
                    if joke.wordCount > 0 {
                        Text("\(joke.wordCount)w")
                            .font(.system(size: 10))
                            .foregroundColor(roastMode ? .white.opacity(0.3) : AppTheme.Colors.textTertiary)
                    }
                    
                    // Date
                    Text(joke.dateModified.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 10))
                        .foregroundColor(roastMode ? .white.opacity(0.35) : AppTheme.Colors.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastCard.opacity(isHit ? 1 : 0) : AppTheme.Colors.surfaceElevated.opacity(isHit ? 1 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .strokeBorder(
                    isHit 
                        ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold).opacity(0.3)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Improved Folder Chip

struct FolderChip: View {
    let name: String
    var icon: String = "folder.fill"
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isSelected 
                            ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                            : (roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.paperAged)
                    )
            )
            .foregroundColor(
                isSelected 
                    ? .white 
                    : (roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
            )
        }
        .buttonStyle(ChipStyle())
    }
}

// MARK: - The Hits Chip (for filter row)

struct TheHitsChip: View {
    let count: Int
    let isSelected: Bool
    var roastMode: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: roastMode ? "flame.fill" : "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isSelected 
                            ? AnyShapeStyle(.white)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: roastMode 
                                        ? [AppTheme.Colors.roastAccent, .orange]
                                        : [AppTheme.Colors.hitsGold, AppTheme.Colors.hitsGoldLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                
                Text("The Hits")
                    .font(.system(size: 13, weight: .semibold))
                
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill((roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold).opacity(0.2))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold)
                            : (roastMode ? AppTheme.Colors.roastCard : AppTheme.Colors.surfaceElevated)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        (roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.hitsGold).opacity(isSelected ? 0 : 0.4),
                        lineWidth: 1.5
                    )
            )
            .foregroundColor(
                isSelected 
                    ? .white 
                    : (roastMode ? .white.opacity(0.9) : AppTheme.Colors.inkBlack)
            )
        }
        .buttonStyle(ChipStyle())
    }
}

// MARK: - Jokes Empty State

struct JokesEmptyState: View {
    var roastMode: Bool = false
    var hasFilter: Bool = false
    var onAddJoke: (() -> Void)? = nil
    
    var body: some View {
        BitBinderEmptyState(
            icon: roastMode ? "flame.fill" : "theatermasks.fill",
            title: hasFilter ? "No jokes here" : (roastMode ? "No roasts yet" : "No jokes yet"),
            subtitle: hasFilter 
                ? "Try a different filter or search term" 
                : (roastMode ? "Add your first target to start writing roasts" : "Start writing your first joke or import from files"),
            actionTitle: hasFilter ? nil : (roastMode ? "Add Target" : "Add Joke"),
            action: onAddJoke,
            roastMode: roastMode,
            iconGradient: roastMode 
                ? AppTheme.Colors.roastEmberGradient 
                : LinearGradient(
                    colors: [AppTheme.Colors.primaryAction, AppTheme.Colors.primaryActionLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
    }
}

// MARK: - Import Progress Overlay

struct ImportProgressCard: View {
    let importFileCount: Int
    let importFileIndex: Int
    let importStatusMessage: String
    let importedJokeNames: [String]
    var roastMode: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                
                Text("Importing...")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(roastMode ? .white : AppTheme.Colors.inkBlack)
            }
            
            // Progress
            VStack(spacing: 8) {
                ProgressView(value: Double(importFileIndex), total: Double(max(1, importFileCount)))
                    .tint(roastMode ? AppTheme.Colors.roastAccent : AppTheme.Colors.primaryAction)
                
                Text(importStatusMessage)
                    .font(.system(size: 14))
                    .foregroundColor(roastMode ? .white.opacity(0.7) : AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Recent imports
            if !importedJokeNames.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(roastMode ? .white.opacity(0.5) : AppTheme.Colors.textTertiary)
                    
                    ForEach(importedJokeNames.suffix(3), id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.Colors.success)
                            Text(name)
                                .font(.system(size: 13))
                                .foregroundColor(roastMode ? .white.opacity(0.8) : AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(roastMode ? AppTheme.Colors.roastSurface : AppTheme.Colors.surfaceElevated)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        )
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
    .background(AppTheme.Colors.paperCream)
}

#Preview("Joke Row") {
    VStack(spacing: 8) {
        JokeRowView(joke: Joke(content: "Why did the chicken cross the road? To get to the other side!", title: "Classic Chicken"))
        JokeRowView(joke: {
            let j = Joke(content: "I told my wife she was drawing her eyebrows too high. She looked surprised.", title: "Eyebrow Joke")
            j.isHit = true
            return j
        }())
    }
    .padding()
    .background(AppTheme.Colors.paperCream)
}
